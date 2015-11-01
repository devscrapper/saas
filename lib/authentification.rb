require_relative 'communication'

class Authentification

  attr_reader :user, :pwd
  def self.get_one(port_server)
    Question.new({"cmd" => "get"}).ask_to(port_server)
  end

  def initialize(user=nil, pwd=nil)
    @user = user
    @pwd = pwd
  end

  def check(port_server)
    Question.new({"cmd" => "check", "authentification" => self}).ask_to(port_server)
  end

  def delete(port_server)
    Information.new({"cmd" => "delete", "authentification" => self}).send_local(port_server)
  end
end