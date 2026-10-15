Pod::Spec.new do |s|
  s.name             = 'quran_whisper'
  s.version          = '0.1.0'
  s.summary          = 'Pengenal bacaan Al-Qur\'an offline (whisper.cpp) untuk Sambung Ayat.'
  s.description      = 'Pembungkus FFI whisper.cpp v1.5.4 untuk aplikasi Sambung Ayat.'
  s.homepage         = 'https://github.com/wantodbz/sambung-ayat'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Abu Syafiq' => 'wantodbz@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.frameworks = 'Accelerate'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/../src" "${PODS_TARGET_SRCROOT}/../src/whisper"',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) NDEBUG=1 GGML_USE_ACCELERATE=1',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++11',
    'GCC_OPTIMIZATION_LEVEL' => '3',
    'OTHER_CFLAGS' => '$(inherited) -fno-finite-math-only',
  }
  s.swift_version = '5.0'
end
