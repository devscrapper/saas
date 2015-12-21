require_relative '../lib/backlink'
require_relative '../lib/error'
require 'em-http-server'
require 'addressable/uri'

class BacklinksConnection < EM::HttpServer::Server
  include Errors
  ARGUMENT_NOT_DEFINE = 1900
  ACTION_UNKNOWN = 1901
  SCRAPED = "scraped-referral" #dans TMP
  TMP = File.expand_path(File.join("..", "..", "tmp"), __FILE__)

  attr :logger,
       :webscraper_factory,
       :geolocation


  def initialize(geolocation, webscraper_factory, logger)
    super
    @logger = logger
    @geolocation = geolocation
    @webscraper_factory = webscraper_factory
  end

  def process_http_request
    #------------------------------------------------------------------------------------------------------------------
    # Check input data
    #------------------------------------------------------------------------------------------------------------------
    begin
      query_values = Addressable::URI.parse("?#{Addressable::URI.unencode_component(@http_query_string)}").query_values

      raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "action"}) if query_values["action"].nil? or query_values["action"].empty?

      case query_values["action"]

        when "scrape"
          raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "hostname"}) if query_values["hostname"].nil? or query_values["hostname"].empty?

        when "evaluate"
          raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "backlink"}) if query_values["backlink"].nil? or query_values["backlink"].empty?
          raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "landing_url"}) if query_values["landing_url"].nil? or query_values["landing_url"].empty?

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
      begin


        case query_values["action"]
          when "scrape"
            webscraper = @webscraper_factory.book(@geolocation)

            results = scrape(query_values["hostname"], webscraper)

          when "evaluate"
            results = evaluate(query_values["backlink"], query_values["landing_url"])

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
        response.content_type 'application/json'
        response.content = results
        response.send_response

      ensure
        @webscraper_factory.free(webscraper) unless webscraper.nil?
        close_connection_after_writing

      end
    end
  end

  def http_request_errback e
    # printing the whole exception
    puts e.inspect
  end


  private
  def scrape(hostname, webscraper)
    @logger.an_event.info "ask backlinks for #{hostname}"

    Backlinks::majestic_ident_authen(webscraper)

    @logger.an_event.info "identification to majestic for #{hostname}"

    opts = {}
    opts.merge!(:geolocation => @geolocation.to_json) unless @geolocation.nil?

    backlinks = Backlinks::scrape(hostname, webscraper, opts)

    @logger.an_event.info "backlinks scraped from majestic for #{hostname}"

    backlinks
  end

  def evaluate(backlink, landing_url)
    @logger.an_event.info "evaluate backlink #{backlink}"

    kw = Backlinks::Backlink.new(backlink)

    kw.evaluate(landing_url, @geolocation.to_json)

    @logger.an_event.info "evaluated backlink #{backlink} : #{landing_url} is backlink ? #{kw.is_a_backlink}"

    kw.is_a_backlink.to_json
  end
end
