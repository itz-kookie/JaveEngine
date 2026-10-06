## RIFF WAVE loading for the formats song packages use: PCM and float go through Godot, and
## Microsoft ADPCM is decoded to 16-bit PCM here.
class_name WavFile
extends RefCounted

const FORMAT_MS_ADPCM := 2
const ADAPTATION: PackedInt32Array = [230, 230, 230, 230, 307, 409, 512, 614, 768, 614, 512, 409, 307, 230, 230, 230]
const DEFAULT_COEF1: PackedInt32Array = [256, 512, 0, 192, 240, 460, 392]
const DEFAULT_COEF2: PackedInt32Array = [0, -256, 0, 64, 0, -208, -232]
const MIN_DELTA := 16
const RUNS := 64
const NIBBLE_SHIFTS: PackedInt32Array = [4, 0]

var format := 0
var channels := 0
var rate := 0
var block_align := 0
var samples_per_block := 0
var fact_samples := 0
var coef1 := DEFAULT_COEF1
var coef2 := DEFAULT_COEF2
var data_offset := 0
var data_size := 0
var bytes := PackedByteArray()


static func load_stream(path: String) -> AudioStream:
	var file_bytes := FileAccess.get_file_as_bytes(path)
	var wav := WavFile.new()
	if not wav.parse(file_bytes) or wav.format != FORMAT_MS_ADPCM:
		return AudioStreamWAV.load_from_buffer(file_bytes)
	return wav.decode()


func parse(file_bytes: PackedByteArray) -> bool:
	bytes = file_bytes
	if bytes.size() < 12 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF" or bytes.slice(8, 12).get_string_from_ascii() != "WAVE":
		return false
	var offset := 12
	while offset + 8 <= bytes.size():
		var id := bytes.slice(offset, offset + 4).get_string_from_ascii()
		var size := bytes.decode_u32(offset + 4)
		var body := offset + 8
		if id == "fmt " and size >= 16:
			_read_format(body, size)
		elif id == "fact" and size >= 4:
			fact_samples = bytes.decode_u32(body)
		elif id == "data":
			data_offset = body
			data_size = mini(size, bytes.size() - body)
		offset = body + size + (size & 1)
	return format != 0 and data_offset > 0 and channels > 0 and rate > 0


func _read_format(body: int, size: int) -> void:
	format = bytes.decode_u16(body)
	channels = bytes.decode_u16(body + 2)
	rate = bytes.decode_u32(body + 4)
	block_align = bytes.decode_u16(body + 12)
	if format != FORMAT_MS_ADPCM or size < 22:
		return
	samples_per_block = bytes.decode_u16(body + 18)
	var count := bytes.decode_u16(body + 20)
	if count == 0 or size < 22 + count * 4:
		return
	coef1 = PackedInt32Array()
	coef2 = PackedInt32Array()
	for index in count:
		coef1.append(bytes.decode_s16(body + 22 + index * 4))
		coef2.append(bytes.decode_s16(body + 24 + index * 4))


## Blocks are independent, so runs of them decode in parallel; null when the header is unusable.
func decode() -> AudioStreamWAV:
	if channels < 1 or channels > 2 or block_align <= 7 * channels:
		return null
	var per_block := (block_align - 7 * channels) * 2 / channels + 2
	if samples_per_block < 2 or samples_per_block > per_block:
		samples_per_block = per_block
	var block_count := ceili(float(data_size) / block_align)
	var run_count := mini(block_count, RUNS)
	var runs: Array[PackedByteArray] = []
	runs.resize(run_count)
	if run_count > 0:
		var task := WorkerThreadPool.add_group_task(_decode_run.bind(runs, block_count), run_count, -1, true, "Decode ADPCM")
		WorkerThreadPool.wait_for_group_task_completion(task)
	var pcm := PackedByteArray()
	for run in runs:
		pcm.append_array(run)
	var frames := pcm.size() / (channels * 2)
	if fact_samples > 0 and fact_samples < frames:
		pcm.resize(fact_samples * channels * 2)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = channels == 2
	stream.data = pcm
	return stream


func _decode_run(run: int, runs: Array[PackedByteArray], block_count: int) -> void:
	var first := block_count * run / runs.size()
	var last := block_count * (run + 1) / runs.size()
	var frame_bytes := channels * 2
	var pcm := PackedByteArray()
	pcm.resize((last - first) * samples_per_block * frame_bytes)
	var out := 0
	for block in range(first, last):
		var start := data_offset + block * block_align
		var end := mini(start + block_align, data_offset + data_size)
		if end - start < 7 * channels:
			break
		out = _decode_stereo(pcm, start, end, out) if channels == 2 else _decode_mono(pcm, start, end, out)
	pcm.resize(out)
	runs[run] = pcm


## Returns the write offset after the block.
func _decode_stereo(pcm: PackedByteArray, start: int, end: int, out: int) -> int:
	var src := bytes
	var p0 := mini(src[start], coef1.size() - 1)
	var p1 := mini(src[start + 1], coef1.size() - 1)
	var c1a := coef1[p0]
	var c2a := coef2[p0]
	var c1b := coef1[p1]
	var c2b := coef2[p1]
	var delta_a := src.decode_s16(start + 2)
	var delta_b := src.decode_s16(start + 4)
	var s1a := src.decode_s16(start + 6)
	var s1b := src.decode_s16(start + 8)
	var s2a := src.decode_s16(start + 10)
	var s2b := src.decode_s16(start + 12)
	pcm.encode_s16(out, s2a)
	pcm.encode_s16(out + 2, s2b)
	pcm.encode_s16(out + 4, s1a)
	pcm.encode_s16(out + 6, s1b)
	out += 8
	var limit := mini(end, start + 14 + (samples_per_block - 2))
	for index in range(start + 14, limit):
		var byte := src[index]
		var nibble := byte >> 4
		var predicted := ((s1a * c1a + s2a * c2a) >> 8) + (nibble - 16 if nibble >= 8 else nibble) * delta_a
		predicted = clampi(predicted, -32768, 32767)
		s2a = s1a
		s1a = predicted
		delta_a = maxi(MIN_DELTA, (ADAPTATION[nibble] * delta_a) >> 8)
		nibble = byte & 15
		var right := ((s1b * c1b + s2b * c2b) >> 8) + (nibble - 16 if nibble >= 8 else nibble) * delta_b
		right = clampi(right, -32768, 32767)
		s2b = s1b
		s1b = right
		delta_b = maxi(MIN_DELTA, (ADAPTATION[nibble] * delta_b) >> 8)
		pcm.encode_u32(out, (predicted & 0xFFFF) | ((right & 0xFFFF) << 16))
		out += 4
	return out


func _decode_mono(pcm: PackedByteArray, start: int, end: int, out: int) -> int:
	var src := bytes
	var predictor := mini(src[start], coef1.size() - 1)
	var c1 := coef1[predictor]
	var c2 := coef2[predictor]
	var delta := src.decode_s16(start + 1)
	var s1 := src.decode_s16(start + 3)
	var s2 := src.decode_s16(start + 5)
	pcm.encode_s16(out, s2)
	pcm.encode_s16(out + 2, s1)
	out += 4
	var limit := mini(end, start + 7 + (samples_per_block - 2) / 2)
	for index in range(start + 7, limit):
		var byte := src[index]
		for shift in NIBBLE_SHIFTS:
			var nibble := (byte >> shift) & 15
			var predicted := clampi(((s1 * c1 + s2 * c2) >> 8) + (nibble - 16 if nibble >= 8 else nibble) * delta, -32768, 32767)
			s2 = s1
			s1 = predicted
			delta = maxi(MIN_DELTA, (ADAPTATION[nibble] * delta) >> 8)
			pcm.encode_s16(out, predicted)
			out += 2
	return out
