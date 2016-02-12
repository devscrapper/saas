require 'rest-client'
require 'socket'
require 'json'

module Supervisor


  def send_online(sender_label)
    activity = {:label => sender_label,
                :state => :online,
                :hostname => Socket.gethostname,
                :time => Time.now
    }
    send(activity)
  end

  def send_failure(sender_label, exception)
    now = Time.now
    activity = {:label => sender_label,
                :state => :fail,
                :hostname => Socket.gethostname,
                :error_label => exception.message,
                :backtrace => exception.backtrace,
                :error_time => now,
                :time => now
    }
    send(activity)
  end

  private
  def send(activity)
    #--------------------------------------------------------------------------------------------------------------------
    # LOAD PARAMETER
    #--------------------------------------------------------------------------------------------------------------------
    begin
      parameters = Parameter.new(__FILE__)

    rescue Exception => e
      $stderr << e.message << "\n"

    else
      $staging = parameters.environment
      $debugging = parameters.debugging
      statupweb_server_ip = parameters.statupweb_server_ip
      statupweb_server_port = parameters.statupweb_server_port

      if statupweb_server_port.nil? or
          statupweb_server_ip.nil? or
          $debugging.nil? or
          $staging.nil?
        $stderr << "some parameters not define" << "\n"
      end
    end


    # informe statupweb du nouvel etat d'un server
    # en cas d'erreur on ne leve pas une exception car cela ne met en peril le comportement fonctionnel de derouelement de lexecution de la policy.
    begin

      response = RestClient.post "http://#{statupweb_server_ip}:#{statupweb_server_port}/activity_servers/",
                                 JSON.generate(activity),
                                 :content_type => :json,
                                 :accept => :json
      raise response.content if response.code != 201

    rescue Exception => e
      $stderr << "not send activity #{activity} to statupweb #{statupweb_server_ip}:#{statupweb_server_port}=> #{e.message}"
    else
      $stdout << "send activity #{activity} to statupweb #{statupweb_server_ip}:#{statupweb_server_port}" if $staging == "development"
    end
  end

  module_function :send_online
  module_function :send_failure
  module_function :send
end