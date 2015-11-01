require 'yaml'
require 'socket'
require 'rest-client'

class Communication

  attr :data_go_yaml,
       :data_go_hash,
       :data_go

  class CommunicationException < StandardError
  end

  def initialize(data_go)
    @data_go_yaml = YAML::dump data_go
    begin
      @data_go_hash = data_go.to_hash
    rescue
      @data_go_hash = nil
    end
    @data_go = data_go
  end

  def send_data_to_TCPSocket_server(remote_ip, remote_port)

    begin
      s = TCPSocket.new remote_ip, remote_port
      s.puts @data_go_yaml
    rescue Exception => e
      raise CommunicationException, "cannot send data to <#{remote_ip}:#{remote_port}> because #{e.message}"
    end
  end

  def send_data_to_http_server(remote_ip, remote_port, path)
    # le path doit commencer par /
    raise CommunicationException, "data <#{@data_go}> cannot be convert to a hash" if @data_go_hash.nil?
    begin
      RestClient.put "http://#{remote_ip}:#{remote_port}#{path}", @data_go
    rescue Exception => e
      raise CommunicationException, "cannot send data to <#{remote_ip}:#{remote_port}> because #{e.message}"
    end
  end
end


class Information < Communication
  class InformationException < StandardError
  end

  def initialize(data_go)
    super(data_go)
  end

  def send_local(remote_port, options=nil)
    send_to("localhost", remote_port, options)
  end

  def send_to(remote_ip, remote_port, options=nil)

    begin
      send_data_to_TCPSocket_server(remote_ip, remote_port) if options.nil?
      send_data_to_http_server(remote_ip, remote_port, options["path"]) if !options.nil? and options["scheme"] == "http"
    rescue Exception => e
      raise InformationException, "cannot send information to <#{remote_ip}:#{remote_port}> because #{e.message}"
    end
  end
end

class Question < Communication
  attr :data_back

  class QuestionException < StandardError
  end

  def initialize(data_go)
    super(data_go)
  end

  def ask_to(remote_ip = "localhost", remote_port)
    begin
      s = TCPSocket.new remote_ip, remote_port
      s.puts @data_go_yaml
      local_port, local_ip = Socket.unpack_sockaddr_in(s.getsockname)
    rescue Exception => e
      raise QuestionException,  "cannot ask question to <#{remote_ip}:#{remote_port}> because #{e.message}"
    end
    begin
      @data_back = ""
      while (line = s.gets)
        @data_back += "#{line}"
      end
      local_port, local_ip = Socket.unpack_sockaddr_in(s.getsockname)
      s.close
    rescue Exception => e
      s.close
      raise QuestionException,  "cannot receive response  from  <#{remote_ip}:#{remote_port}> because #{e.message}"
    end
    YAML::load @data_back
  end

end
