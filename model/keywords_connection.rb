#encoding:UTF-8
require_relative '../lib/keyword'
require_relative '../lib/error'
require 'em-http-server'
require 'em/deferrable'
require 'addressable/uri'

class KeywordsConnection < EM::HttpServer::Server
  include Errors
  ARGUMENT_NOT_DEFINE = 1800
  ACTION_UNKNOWN = 1801
  ACTION_NOT_EXECUTE = 1802
  SCRAPED = "scraped-organic" #dans TMP
  TMP = File.expand_path(File.join("..", "..", "tmp"), __FILE__)

  attr :logger,
       :webscraper_factory,
       :geolocation


  def initialize(geolocation, webscraper_factory, logger)
    @logger = logger
    super
    @geolocation = geolocation
    @webscraper_factory = webscraper_factory
  end

  def process_http_request
    #------------------------------------------------------------------------------------------------------------------
    # Check input data
    #------------------------------------------------------------------------------------------------------------------
    begin
      query_values = Addressable::URI.parse("?#{Addressable::URI.unencode_component(@http_query_string)}").query_values

      @logger.an_event.debug "query_values #{query_values}"

      raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "action"}) if query_values["action"].nil? or query_values["action"].empty?

      @logger.an_event.debug "check data for <#{query_values["action"]}> action"
      case query_values["action"]

        when "scrape", "count"

          raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "hostname"}) if query_values["hostname"].nil? or query_values["hostname"].empty?

        when "suggest"

          raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "keywords"}) if query_values["keywords"].nil? or query_values["keywords"].empty?

        when "evaluate"

          raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "keywords"}) if query_values["keywords"].nil? or query_values["keywords"].empty?
          raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "domain"}) if query_values["domain"].nil? or query_values["domain"].empty?
          raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "type"}) if query_values["type"].nil? or query_values["type"].empty?

        when "search"

          raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "keywords"}) if query_values["keywords"].nil? or query_values["keywords"].empty?
          if query_values["engines"].nil? or query_values["engines"].empty?
            query_values["engines"] = [:google, :yahoo, :bing]

          else
            query_values["engines"] = query_values["engines"].split("|").map! { |e| e.to_sym }

          end
          if query_values["count_pages"].nil? or query_values["count_pages"].empty?
            query_values["count_pages"] = 1

          else
            query_values["count_pages"] = query_values["count_pages"].to_i

          end

          @logger.an_event.debug "query_values #{query_values}"

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
      @logger.an_event.debug "execution <#{query_values["action"]}> action"

      case query_values["action"]
        #http://localhost:9251/?action=scrape&hostname=dfijgmsdfjgmdfjgdfljbdfljbgdfljbdflg
        when "scrape", "count"
          # une seule instance de scrape à la fois car un seul id utilisateur pour semrush qui interdit le scrape concurrent
          begin

            case query_values["action"]
              when "scrape"
                webscrapers = @webscraper_factory.book(1, @geolocation)

                @logger.an_event.debug "count book webscrapers #{webscrapers.count}"

                results = scrape(query_values["hostname"], webscrapers)

              when "count"
                webscrapers = @webscraper_factory.book(1, @geolocation)

                @logger.an_event.debug "count book webscrapers #{webscrapers.count}"

                results = count(query_values["hostname"], webscrapers)

            end


          rescue Exception => e
            @logger.an_event.error e.message
            response = EM::DelegatedHttpResponse.new(self)
            response.status = 500
            response.content_type 'application/json'
            response.content = e.to_json
            response.send_response

          else
            @logger.an_event.debug results
            response = EM::DelegatedHttpResponse.new(self)
            response.status = 200
            response.content_type 'application/json'
            response.content = results
            response.send_response

          ensure
            @webscraper_factory.free(webscrapers) unless webscrapers.nil?
            @logger.an_event.debug "free #{webscrapers.count} webscraper(s)"

          end
        # http://#{saas_host}:#{saas_port}/?action=suggest&keywords=#{keyword}
        # http://#{saas_host}:#{saas_port}/?action=evaluate&keywords=#{@words}&domain=#{domain}&type=#{sea|link}
        # http://#{saas_host}:#{saas_port}/?action=online
        # http://#{saas_host}:#{saas_port}/?action=search&keywords=#{keywords}&engines=#{engines}&count_pages=#{count_pages}
        when "suggest", "evaluate", "online", "search"
          # autorise une execution concurrente de plusieurs demande
          action = proc {
            begin
              # perform a long-running operation here, such as a database query.


              case query_values["action"]
                when "suggest"

                  webscrapers = @webscraper_factory.book(1, @geolocation)

                  @logger.an_event.debug "count book webscrapers #{webscrapers.count}"

                  results = suggest(query_values["keywords"], webscrapers)

                when "evaluate"

                  case query_values["type"]
                    when "link"
                      webscraper_count = 3

                    when "sea"
                      webscraper_count = 1

                  end
                  webscrapers = @webscraper_factory.book(webscraper_count, @geolocation)

                  @logger.an_event.debug "count book webscrapers #{webscrapers.count}"

                  results = evaluate(query_values["keywords"],
                                     query_values["domain"],
                                     query_values["type"], webscrapers)

                when "online"
                  results = "OK"

                when "search"

                  webscrapers = @webscraper_factory.book(query_values["engines"].count, @geolocation)

                  @logger.an_event.debug "count book webscrapers #{webscrapers.count}"

                  results = search(query_values["engines"],
                                   query_values["keywords"],
                                   query_values["count_pages"], webscrapers)
              end

            rescue Error => e
              @logger.an_event.error e.message

              results = e

            rescue Exception => e
              @logger.an_event.error e.message
              results = Error.new(ACTION_NOT_EXECUTE, :values => {:action => query_values["action"]}, :error => e)

            else
              results # as usual, the last expression evaluated in the block will be the return value.

            ensure
              @logger.an_event.debug "free #{webscrapers.count} webscraper(s) : "

              webscrapers.each { |webscraper| @webscraper_factory.free(webscraper) } unless webscrapers.nil?

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
  def scrape(hostname, webscrapers)
    @logger.an_event.info "ask keywords for #{hostname}"

    Keywords::semrush_ident_authen(webscrapers[0])

    @logger.an_event.info "identification to semrush for #{hostname}"

    opts = {}
    opts.merge!(:geolocation => @geolocation.to_json) unless @geolocation.nil?

    keywords_arr = Keywords::scrape(hostname, webscrapers[0], opts)

    @logger.an_event.info "keywords scraped from semrush for #{hostname}"

    keywords_arr
  end

  def count(hostname, webscrapers)
    @logger.an_event.info "count keywords for #{hostname}"

    Keywords::semrush_ident_authen(webscrapers[0])

    @logger.an_event.info "identification to semrush for #{hostname}"

    opts = {:range => :selection}
    opts.merge!(:geolocation => @geolocation.to_json) unless @geolocation.nil?

    keywords_arr = Keywords::scrape(hostname, webscrapers[0], opts)

    @logger.an_event.info "count keywords scraped from semrush for #{hostname}"

    {:count => keywords_arr.size}.to_json
  end

  def search(engines, keywords, count_pages, webscrapers)
    @logger.an_event.info "search keywords for #{keywords}"

    s = Time.now

    kw = Keywords::Keyword.new(keywords)


    kw.search(engines, count_pages, webscrapers)

    e = Time.now

    delay = e - s

    p "delay search : #{delay}"
    @logger.an_event.info "search keywords #{keywords} is #{kw.results}"

    kw.results.to_json
  end

  def suggest(keywords, webscrapers)
    @logger.an_event.info "suggest keywords for #{keywords}"

    keywords_arr = Keywords::suggest(keywords, webscrapers[0])

    @logger.an_event.info "suggested #{keywords_arr.size} keywords for #{keywords}"

    keywords_arr
  end

  def evaluate(keywords, domain, type, webscrapers)
    @logger.an_event.info "evaluate keywords #{keywords}"

    kw = Keywords::Keyword.new(keywords)

    case type
      when "link"
        kw.evaluate_link(domain, webscrapers)

      when "sea"
        kw.evaluate_sea(domain, webscrapers[0])

    end


    @logger.an_event.info "evaluation keywords #{keywords} is #{kw.engines}"

    kw.engines.to_json

  end

end


