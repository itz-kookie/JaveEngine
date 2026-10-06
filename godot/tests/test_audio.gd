extends "res://tests/test_base.gd"

const NEON_STEPS_AUDIO := "res://content/songs/neon-steps/Inst.wav"


func run() -> void:
	_test_mono_block()
	_test_stereo_block()
	_test_fact_trims_padding()
	_test_pcm_passes_through()


## Coefficients 256/0 predict the previous sample; each nibble adds nibble * delta and delta never drops below 16.
func _test_mono_block() -> void:
	var block := PackedByteArray([0])
	block.append_array(_s16([16, 100, 50]))
	block.append_array(PackedByteArray([0x12, 0xF0]))
	var stream := _decode(_adpcm_wav(1, block.size(), [block], 0))
	check(stream != null and not stream.stereo, "mono MS ADPCM decodes")
	if stream != null:
		check(_samples(stream) == [50, 100, 116, 148, 132, 132], "mono samples (got %s)" % [_samples(stream)])


## Stereo blocks interleave the header per channel and take the high nibble for the left channel.
func _test_stereo_block() -> void:
	var block := PackedByteArray([0, 1])
	block.append_array(_s16([16, 32, 10, -10, 0, 0]))
	block.append_array(PackedByteArray([0x1F]))
	var stream := _decode(_adpcm_wav(2, block.size(), [block], 0))
	check(stream != null and stream.stereo, "stereo MS ADPCM decodes")
	if stream != null:
		# Right uses predictor 1 (512, -256): ((-10 * 512 + 0 * -256) >> 8) - 32 = -52.
		check(_samples(stream) == [0, 0, 10, -10, 26, -52], "stereo samples (got %s)" % [_samples(stream)])
		check_near(stream.get_length(), 3.0 / 8000.0, "length from decoded frames")


func _test_fact_trims_padding() -> void:
	var block := PackedByteArray([0])
	block.append_array(_s16([16, 100, 50]))
	block.append_array(PackedByteArray([0x12, 0xF0]))
	var stream := _decode(_adpcm_wav(1, block.size(), [block], 3))
	check(stream != null and _samples(stream) == [50, 100, 116], "fact chunk sample count trims the last block")


func _test_pcm_passes_through() -> void:
	var stream := WavFile.load_stream(NEON_STEPS_AUDIO)
	check(stream is AudioStreamWAV and stream.get_length() > 20.0, "PCM WAV still loads through Godot")


func _decode(bytes: PackedByteArray) -> AudioStreamWAV:
	var wav := WavFile.new()
	return wav.decode() if wav.parse(bytes) and wav.format == WavFile.FORMAT_MS_ADPCM else null


static func _samples(stream: AudioStreamWAV) -> Array[int]:
	var values: Array[int] = []
	for offset in range(0, stream.data.size(), 2):
		values.append(stream.data.decode_s16(offset))
	return values


static func _s16(values: Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(values.size() * 2)
	for index in values.size():
		bytes.encode_s16(index * 2, values[index])
	return bytes


static func _adpcm_wav(channels: int, block_align: int, blocks: Array, fact_samples: int) -> PackedByteArray:
	var format := PackedByteArray()
	format.resize(20)
	format.encode_u16(0, WavFile.FORMAT_MS_ADPCM)
	format.encode_u16(2, channels)
	format.encode_u32(4, 8000)
	format.encode_u32(8, 4000 * channels)
	format.encode_u16(12, block_align)
	format.encode_u16(14, 4)
	format.encode_u16(16, 2)
	format.encode_u16(18, (block_align - 7 * channels) * 2 / channels + 2)
	var data := PackedByteArray()
	for block: PackedByteArray in blocks:
		data.append_array(block)
	var body := "WAVE".to_ascii_buffer()
	body.append_array(_chunk("fmt ", format))
	if fact_samples > 0:
		var fact := PackedByteArray()
		fact.resize(4)
		fact.encode_u32(0, fact_samples)
		body.append_array(_chunk("fact", fact))
	body.append_array(_chunk("data", data))
	return _chunk("RIFF", body)


static func _chunk(id: String, body: PackedByteArray) -> PackedByteArray:
	var bytes := id.to_ascii_buffer()
	var size := PackedByteArray()
	size.resize(4)
	size.encode_u32(0, body.size())
	bytes.append_array(size)
	bytes.append_array(body)
	if body.size() % 2 == 1:
		bytes.append(0)
	return bytes
