#encoding:UTF-8

require_relative '../lib/error'
require 'em-http-server'
require 'em/deferrable'
require 'addressable/uri'

class ProxiesConnection < EM::HttpServer::Server
  include Errors
  ARGUMENT_NOT_DEFINE = 1800
  ACTION_UNKNOWN = 1801
  ACTION_NOT_EXECUTE = 1802

  attr :logger


  def initialize(logger)
    @logger = logger
    super
  end

  def process_http_request
    #------------------------------------------------------------------------------------------------------------------
    # Check input data
    #------------------------------------------------------------------------------------------------------------------
    begin
      @logger.an_event.debug "query string : #{@http_query_string}"
      #TODO gerer les caractere encodé en http exe url :  http://192.168.1.88:9253/?action=scrape&&url=http://centre.epilation-laser-definitive.info/ville-971-saint_fran&ccedil;ois.htm&host=http://www.epilation-laser-definitive.info/&schemes=http&types=global&count=0
      query_values = Addressable::URI.parse("?#{Addressable::URI.unencode_component(@http_query_string)}").query_values

      raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "action"}) if query_values["action"].nil? or query_values["action"].empty?

      case query_values["action"]
        when "online"

        when "scrape"

        else
          raise Error.new(ACTION_UNKNOWN, :values => {:action => query_values["action"]})

      end

    rescue Exception => e

      @logger.an_event.error e.message

      response = EM::DelegatedHttpResponse.new(self)

      case e.code
        when ACTION_UNKNOWN
          response.status = 501

        when ARGUMENT_NOT_DEFINE
          response.status = 400

      end
      response.content_type 'application/json'
      response.content = e.to_json
      response.send_response

    else
      ##http://#{saas_host}:#{saas_port}/?action=online
      #http://192.168.1.88:9254/?action=scrape
      case query_values["action"]
        when "online"
          results = "OK"

        when "scrape"
          # autorise une execution concurrente de plusieurs demande

          action = proc {
            begin
              # perform a long-running operation here, such as a database query.

              results = scrape

            rescue Error => e
              results = e

            rescue Exception => e
              results = Error.new(ACTION_NOT_EXECUTE, :values => {:action => query_values["action"]}, :error => e)

            else
              results # as usual, the last expression evaluated in the block will be the return value.

            ensure

            end
          }

          callback = proc { |results|
            # do something with result here, such as send it back to a network client.

            response = EM::DelegatedHttpResponse.new(self)

            if results.is_a?(Error)
              response.content_type 'application/json'
              response.status = 500
              response.content = results.to_json

            else
              response.status = 200
              response.content_type 'application/json'
              response.content = results

            end

            response.send_response
            close_connection_after_writing
          }

          EM.defer(action, callback)


      end

    end
  end

  def http_request_errback e
    # printing the whole exception
    puts e.inspect
  end


  private
  def scrape
    proxy_list = File.open(File.join(TMP,"proxy_list"), "r:bom|utf-8")
    proxies = proxy_list.read
    proxy_list.close
    proxies
  end


end


