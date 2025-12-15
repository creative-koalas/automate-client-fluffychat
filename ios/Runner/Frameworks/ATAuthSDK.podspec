Pod::Spec.new do |s|
  s.name             = 'ATAuthSDK'
  s.version          = '2.14.12'
  s.summary          = 'Aliyun Phone Number Authentication SDK'
  s.description      = 'Aliyun One-Click Login SDK for iOS'
  s.homepage         = 'https://help.aliyun.com/document_detail/85063.html'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'Aliyun' => 'support@aliyun.com' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '11.0'
  s.static_framework = true

  s.vendored_frameworks = [
    'ATAuthSDK.xcframework',
    'YTXMonitor.xcframework',
    'YTXOperators.xcframework'
  ]

  s.resource_bundles = {
    'ATAuthSDK' => ['ATAuthSDK.xcframework/ios-arm64/ATAuthSDK.framework/ATAuthSDK.bundle/*']
  }

  s.frameworks = 'Foundation', 'UIKit', 'CoreTelephony', 'SystemConfiguration', 'CoreGraphics', 'Security', 'Network'
  s.libraries = 'z', 'c++'

  s.pod_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
end
