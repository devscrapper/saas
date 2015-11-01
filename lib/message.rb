require 'singleton'
require 'pathname'
require 'yaml'
class Messages
  include Singleton

  MESSAGES_REPO = File.expand_path(File.join("..", "..", "repository", "message.yml"), __FILE__)

  attr :messages

  def initialize

    raise "repository messages not found" unless File.exist?(MESSAGES_REPO)

       begin
         @messages = YAML::load(File.open(MESSAGES_REPO), "r")
       rescue Exception => e
         raise "failed to load repository messages #{e.message}"
       end

  end

  #remplace les variables par les valeurs contenues dans values dans le message identifié par le code
  def [](code, values={})
    m = @messages[code].dup
    values.each_pair{|var, val| m.gsub!("[#{var.to_s}]", "[#{val}]")}
    m
  end
end

