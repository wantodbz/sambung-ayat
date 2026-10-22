import 'platform.dart';

SpeechEngine createSpeechEngine() => throw UnsupportedError('platform');
MurottalPlayer createMurottalPlayer() => throw UnsupportedError('platform');
MurajaahIO createMurajaahIO() => throw UnsupportedError('platform');
const bool streamsAudio = false;
bool browserSpeech() => false;
Future<void> keepScreenOn(bool on) async {}
