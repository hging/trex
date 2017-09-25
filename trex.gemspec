Gem::Specification.new do |s|
  s.name        = 'trex'
  s.version     = '0.0.1'
  s.date        = '2017-09-08'
  s.summary     = "Bittrex WebSocket and REST API Library"
  s.description = ""
  s.authors     = ["ppibburr"]
  s.email       = 'tulnor33@gmail.com'
  s.files       = ["lib/trex.rb","lib/trex/json_api.rb", "lib/trex/account.rb", "lib/trex/socket_api.rb", "data/get_cookies.js"].push(*Dir.glob('vendor/**/*')).push(*Dir.glob('bin/**/*'))
  s.homepage    = 'http://github.com/ppibburr/trex'
  s.license       = 'MIT'
end
