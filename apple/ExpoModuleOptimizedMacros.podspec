require 'json'

package = JSON.parse(File.read(File.join(__dir__, '..', 'package.json')))

Pod::Spec.new do |s|
  s.name           = 'ExpoModuleOptimizedMacros'
  s.version        = package['version']
  s.summary        = package['description']
  s.description    = package['description']
  s.license        = package['license']
  s.author         = package['author']
  s.homepage       = package['homepage']
  s.platforms      = {
    :ios => '15.1',
    :tvos => '15.1',
    :osx => '11.0',
  }
  s.source         = { git: 'https://github.com/expo/expo-module-optimized-macros-plugin.git' }
  s.source_files   = 'Sources/ExpoModulesOptimized/**/*.swift'
end
