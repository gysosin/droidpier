Pod::Spec.new do |s|
  s.name = 'open_dex_texture'
  s.version = '0.1.0'
  s.summary = 'Native frame textures for DroidPier.'
  s.description = 'A local FIFO reader that presents Android frames through Flutter textures.'
  s.homepage = 'https://github.com/gysosin/droidpier'
  s.license = { :type => 'Apache-2.0', :file => '../../../LICENSE' }
  s.author = { 'DroidPier Contributors' => 'gysosin@users.noreply.github.com' }
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '12.0'
  s.swift_version = '5.0'
end
