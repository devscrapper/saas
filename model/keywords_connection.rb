require_relative '../lib/keyword'
require_relative '../lib/error'
require 'em-http-server'
require 'addressable/uri'

class KeywordsConnection < EM::HttpServer::Server
  include Errors
  ARGUMENT_NOT_DEFINE = 1800
  ACTION_UNKNOWN = 1801
  SCRAPED = "scraped-organic" #dans TMP
  TMP = File.expand_path(File.join("..", "..", "tmp"), __FILE__)

  attr :logger,
       :geolocation_factory,
       :webscraper_factory,
       :geolocation


  def initialize(geolocation_factory, webscraper_factory, logger)
      @logger = logger

    super


    @geolocation_factory = geolocation_factory
    @geolocation = @geolocation_factory.nil? ? nil : @geolocation_factory.get
    @webscraper_factory = webscraper_factory

  end

  def process_http_request
    begin
      query_values = Addressable::URI.parse("?#{Addressable::URI.unencode_component(@http_query_string)}").query_values

      raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "action"}) if query_values["action"].nil? or query_values["action"].empty?

      case query_values["action"]
        when "scrape"
          raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "hostname"}) if query_values["hostname"].nil? or query_values["hostname"].empty?

          @webscraper = @webscraper_factory.book(@geolocation)
          results = scrape(query_values["hostname"])

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
        else
          response.status = 500
      end

      response.content_type 'application/json'
      response.content = e.to_json
      response.send_response

    else
      response = EM::DelegatedHttpResponse.new(self)
      response.status = 200
      response.content_type 'application/text'
      response.content = results
      response.send_response

    ensure
      @webscraper_factory.free(@webscraper) unless @webscraper.nil?
      close_connection_after_writing

    end

  end

  def http_request_errback e
    # printing the whole exception
    puts e.inspect
  end


  private
  def scrape(hostname)
    @logger.an_event.info "ask keywords for #{hostname}"

    Keywords::semrush_ident_authen(@webscraper)

    @logger.an_event.info "identification to semrush for #{hostname}"

    opts = {}
    opts.merge!(:geolocation => @geolocation.to_json) unless @geolocation.nil?

    keywords = Keywords::scrape(hostname, @webscraper, opts)

    @logger.an_event.info "keywords scraped from semrush for #{hostname}"

    keywords
  end

end
