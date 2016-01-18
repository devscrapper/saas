#encoding:UTF-8

require_relative '../lib/error'
require_relative '../lib/link'
require 'em-http-server'
require 'em/deferrable'
require 'addressable/uri'

class LinksConnection < EM::HttpServer::Server
  include Errors
  ARGUMENT_NOT_DEFINE = 1800
  ACTION_UNKNOWN = 1801
  ACTION_NOT_EXECUTE = 1802

  attr :logger,
       :geolocation


  def initialize(geolocation, logger)
    @logger = logger
    super
    @geolocation = geolocation
  end

  def process_http_request
    #------------------------------------------------------------------------------------------------------------------
    # Check input data
    #------------------------------------------------------------------------------------------------------------------
    begin
      #TODO gerer les caractere encodé en http exe url :  http://192.168.1.88:9253/?action=scrape&&url=http://centre.epilation-laser-definitive.info/ville-971-saint_fran&ccedil;ois.htm&host=http://www.epilation-laser-definitive.info/&schemes=http&types=global&count=0
      query_values = Addressable::URI.parse("?#{Addressable::URI.unencode_component(@http_query_string)}").query_values

      raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "action"}) if query_values["action"].nil? or query_values["action"].empty?

      case query_values["action"]
        when "online"

        when "scrape"
          raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "url"}) if query_values["url"].nil? or query_values["url"].empty?
          raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "host"}) if query_values["host"].nil? or query_values["host"].empty?
          raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "schemes"}) if query_values["schemes"].nil? or query_values["schemes"].empty?
          raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "types"}) if query_values["types"].nil? or query_values["types"].empty?
          raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "count"}) if query_values["count"].nil? or query_values["count"].empty?

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
      #http://192.168.1.88:9253/?action=scrape&&url=http://centre-manche.epilation-laser-definitive.info/ville-50-cherbourg_octeville.htm&host=http://www.epilation-laser-definitive.info/&schemes=http&types=global&count=0
      case query_values["action"]
        when "online"
          results = "OK"

        when "scrape"
          # autorise une execution concurrente de plusieurs demande

          action = proc {
            begin
              # perform a long-running operation here, such as a database query.

              results = scrape(query_values["url"],
                               query_values["host"],
                               query_values["types"].split('|').map! { |t| t.to_sym },
                               query_values["schemes"].split('|').map! { |s| s.to_sym },
                               query_values["count"].to_i)

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
  def scrape(url, host, types, schemes, count)
    @logger.an_event.info "ask url for #{url}"

    opts = {}
    opts.merge!(:geolocation => @geolocation.to_json) unless @geolocation.nil?

    page = Links::scrape(url, host, types, schemes, count, opts)

    @logger.an_event.info "#{page.links.size} links scraped for #{url}"

    page.to_json
  end


end


