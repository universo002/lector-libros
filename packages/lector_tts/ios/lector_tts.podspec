Pod::Spec.new do |s|
  s.name             = 'lector_tts'
  s.version          = '0.0.1'
  s.summary          = 'Voz nativa de iOS para Lector.'
  s.description      = 'Cola de AVSpeechSynthesizer con pausas, interrupciones y auriculares.'
  s.homepage         = 'https://github.com/universo002/lector-libros'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Lector' => 'lector@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
