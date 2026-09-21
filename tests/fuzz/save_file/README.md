# Fuzz corpus: save file loader

Each file is a hostile or malformed save that `SaveFile.parse()` or
`SimAssembly.load_save()` must reject with a message and without crashing (engineering
standards §3.5, §5.1). `tests/sim/test_save_file.gd` loads every `*.json` here on each
run. Add every misbehaving input found by fuzzing or a bug report here permanently.
