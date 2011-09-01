require './lib/takeoff'
Gem::Specification.new do |s|
  s.name              = "takeoff"
  s.version           = "0.1.0"
  s.date              = "2011-08-31"
  s.summary           = "The best damn presentation software a developer could ever love - and then some more."
  s.homepage          = "http://github.com/pote/takeoff"
  s.email             = "poteland@gmail.com"
  s.authors           = ["Scott Chacon", "Pablo Astigarraga"]
  s.has_rdoc          = false
  s.require_path      = "lib"
  s.executables       = %w( takeoff )
  s.files             = %w( README.rdoc Rakefile LICENSE )
  s.files            += Dir.glob("lib/**/*")
  s.files            += Dir.glob("bin/**/*")
  s.files            += Dir.glob("views/**/*")
  s.files            += Dir.glob("public/**/*")
  s.add_dependency      "sinatra"
  s.add_dependency      "bluecloth"
  s.add_dependency      "nokogiri"
  s.add_dependency      "json"
  s.add_dependency("gli",">= 1.2.5")
  s.add_development_dependency "mg"
  s.description       = <<-desc
  TakeOff is a fork of ShowOff, a Sinatra web app that reads simple configuration
  files for a presentation, it was written by Scott Chacon and it lives at 
  https://github.com/schacon/showoff.

  TakeOff implements Airplay, a gem that streams content into an AppleTv - and 
  soon to any computer running an AirServer, this gem was written by Bruno Aguirre
  and is maintained at https://github.com/elcuervo/airplay. The goal is to stream
  your presentation's slides to a remote AppleTv/Computer hooked up to a projector
  without the need for physical cables and while being able to browse through your
  notes without it being noticed.
  desc
end
