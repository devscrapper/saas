#encoding:utf-8
require 'net/http'
require 'nokogiri'
require 'addressable/uri'
require 'ruby-progressbar'
require 'thread'
require 'csv'
require 'open-uri'
require 'openssl'
require 'user_agent_randomizer'
require_relative 'error'

module Backlinks
  include Errors
  include Addressable
  ARGUMENT_NOT_DEFINE = 1600
  BAD_GEOLOCATION = 1601
  BAD_URL_BACKLINK = 1602
  BACKLINK_NOT_EVALUATED = 1603
  IDENTIFICATION_FAILED = 1604
  BACKLINK_NOT_SCRAPED = 1605
  #----------------------------------------------------------------------------------------------------------------
  # scrape(hostname, driver, opts)
  #----------------------------------------------------------------------------------------------------------------
  # fournit la liste des baclinks d'un domaine au moyen de majetic.com
  #----------------------------------------------------------------------------------------------------------------
  # input :
  # un domaine sans http
  # une instance de webdriver
  # un hash d'options : {:ip => @ip d proxy, :port => num port du proxy}, nil sinon
  # output :
  # StringIO contenant lesdonnées fournies par majestic
  #----------------------------------------------------------------------------------------------------------------
  #----------------------------------------------------------------------------------------------------------------
  def scrape(hostname, driver, opts={})
    init_logging

    proxy = nil
    type_proxy = nil
    backlinks = nil


    if !opts[:geolocation].nil?
      type_proxy, proxy = proxy(opts[:geolocation])
      @logger.an_event.debug "type proxy #{type_proxy}, proxy #{proxy}" if !type_proxy.nil? and !proxy.nil?
    end


    begin
      #recherche du domaine sans http sur majectic
      # input = driver.find_element(:id, 'search_text')
      # input.clear
      # input.send_keys hostname
      # driver.find_element(:css, "input[type='submit']").click


      driver.navigate_to "https://fr.majestic.com/reports/site-explorer/top-backlinks?q=#{hostname}"
      @logger.an_event.debug "navigate to #{driver.current_url}"

      @logger.an_event.debug "search in majestic #{hostname}"

      #creation manuelle de la requete GET pour telecharger le fichier, car phantomjs ne sais pas telecharger des fichiers
      # contrairement à Firefox.
      stok_cookie= driver.manage().cookie_named("STOK");
      ruri_cookie= driver.manage().cookie_named("RURI");
      uri = URI.join("https://fr.majestic.com", "data-output")
      uri.query = URI.form_encode("format" => "Csv",
                                  "MaxSourceURLsPerRefDomain" => "1",
                                  "UsePrefixScan" => "0",
                                  "index_data_source" => "Fresh",
                                  "item" => hostname,
                                  "mode" => "0",
                                  "request_name" => "ExplorerBacklinks",
                                  "show_topical_trust_flow" => "1",
                                  "RefDomain" => "")
      @logger.an_event.debug "uri backlinks csv file majestic : #{uri.to_s}"

      #execution de la requete Get et rangement de son contenu retour dans une variable string
      if !type_proxy.nil? and !proxy.nil?
        backlinks = open(uri.to_s,
                         "Host" => "fr.majestic.com", # n'est pas obligatoire
                         "User-Agent" => driver.user_agent, # n'est pas obligatoire
                         "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", # n'est pas obligatoire
                         "Accept-Language" => "en-US,en;q=0.5", # n'est pas obligatoire
                         "Connection" => "keep-alive", # n'est pas obligatoire
                         "Content-Type" => "application/x-www-form-urlencoded",
                         "Accept-Encoding" => "gzip, deflate", # n'est pas obligatoire
                         "Cookie" => URI.encode("#{ruri_cookie[:name]}=#{ruri_cookie[:value]};#{stok_cookie[:name]}=#{stok_cookie[:value]}"), #est OBLIGATOIRE
                         type_proxy => proxy,
                         :ssl_verify_mode => OpenSSL::SSL::VERIFY_NONE).read
      end
      if type_proxy.nil? and proxy.nil?
        backlinks = open(uri.to_s,
                         "Host" => "fr.majestic.com", # n'est pas obligatoire
                         "User-Agent" => driver.user_agent, # n'est pas obligatoire
                         "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", # n'est pas obligatoire
                         "Accept-Language" => "en-US,en;q=0.5", # n'est pas obligatoire
                         "Connection" => "keep-alive", # n'est pas obligatoire
                         "Content-Type" => "application/x-www-form-urlencoded",
                         "Accept-Encoding" => "gzip, deflate", # n'est pas obligatoire
                         "Cookie" => URI.encode("#{ruri_cookie[:name]}=#{ruri_cookie[:value]};#{stok_cookie[:name]}=#{stok_cookie[:value]}"),
                         :ssl_verify_mode => OpenSSL::SSL::VERIFY_NONE).read
      end
      @logger.an_event.debug "backlinks csv file majestic downloaded"


    rescue Exception => e
      raise Error.new(BACKLINK_NOT_SCRAPED, :values => {:hostname => hostname}, :error => e)
    else
      temp_file = Tempfile.new(['scraped_backlink_from_majestic', '.csv'])
      temp_file.write backlinks
      temp_file.close
      t = []
      f = File.open(temp_file.path,
                    "r:bom|utf-8")
      f.each { |line|
        t << CSV.parse_line(line, {converters: :numeric,
                                   force_quotes: :true,
                                   encoding: "utf-8"}) if f.lineno > 1
      }
      # header du fichier majestic
      #"SourceURL","AnchorText","SourceTrustFlow","SourceCitationFlow","Domain","DomainTrustFlow","DomainCitationFlow","FirstIndexedDate","LinkType","LinkSubType","TargetURL","TargetTrustFlow","TargetCitationFlow","FlagRedirect","FlagFrame","FlagNoFollow","FlagImages","FlagDeleted","FlagAltText","LastSeenDate","FlagMention","DateLost","ReasonLost","SourceTopicalTrustFlow_Topic_0","SourceTopicalTrustFlow_Value_0","DomainTopicalTrustFlow_Topic_0","DomainTopicalTrustFlow_Value_0","DomainTopicalTrustFlow_Topic_1","DomainTopicalTrustFlow_Value_1","DomainTopicalTrustFlow_Topic_2","DomainTopicalTrustFlow_Value_2","DomainTopicalTrustFlow_Topic_3","DomainTopicalTrustFlow_Value_3","DomainTopicalTrustFlow_Topic_4","DomainTopicalTrustFlow_Value_4","TargetTopicalTrustFlow_Topic_0","TargetTopicalTrustFlow_Value_0"
      # row[10] = TargetURL, row[0] = SourceURL dans le fichier issu de majestic
      t.map { |row| [row[10], row[0]] }

    end
  end

  def scrape_as_saas(hostname)
    init_logging
    #"www.epilation-laser-definitive.info"

    try_count = 3
    begin
      parameters = Parameter.new(__FILE__)
      saas_host = parameters.saas_host.to_s
      saas_port = parameters.saas_port.to_s

      raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "hostname"}) if hostname.nil? or hostname.empty?

      #query http vers backlinks saas
      href = "http://#{saas_host}:#{saas_port}/?action=scrape&hostname=#{hostname}"
      @logger.an_event.debug "uri backlinks csv file majestic : #{href}"

      results = open(href,
                     "r:utf-8")

    rescue Exception => e
      @logger.an_event.warn "scrape backlinks for #{hostname} : #{e.message}"
      sleep 5
      try_count -= 1
      retry if try_count > 0
      @logger.an_event.error "scrape backlinks for #{hostname} : #{e.message}"
      raise Error.new(BACKLINK_NOT_SCRAPED, :values => {:hostname => hostname}, :error => e)

    else
      @logger.an_event.info "scrape backlinks for #{hostname}"
      JSON.parse(results.read)

    end
  end


  def majestic_ident_authen(driver)
    init_logging

    begin
      parameters = Parameter.new(__FILE__)
      user = parameters.majestic_user
      pwd = parameters.majestic_pwd


      driver.navigate_to "https://fr.majestic.com/"; @logger.an_event.debug "navigate to #{driver.current_url}"
      @logger.an_event.debug "page source of url #{driver.current_url} : #{driver.page_source}"
      driver.find_element(:id, "login_header_dropdown").click; @logger.an_event.debug "click on login_header_dropdown"
      email = driver.find_element(:name, "EmailAddress")
      email.clear
      email.send_keys user; @logger.an_event.debug "set EmailAddress by #{user}"
      password = driver.find_element(:name, "Password")
      password.clear
      password.send_keys pwd; @logger.an_event.debug "set Password by #{pwd}"
      checkbox = driver.find_element(:id, 'RememberMe')
      checkbox.click; @logger.an_event.debug "click on checkbox RemenberMe"
      button = driver.find_element(:id, "signin_submit")
      button.submit; @logger.an_event.debug "submit signin"

    rescue Exception => e
      @logger.an_event.debug "page source of url #{driver.current_url} : #{driver.page_source}"
      raise Error.new(IDENTIFICATION_FAILED, :values => {:user => user}, :error => e)
    else

    ensure

    end
  end

  private
  def init_logging
    parameters = Parameter.new(__FILE__)
    @logger = Logging::Log.new(self, :staging => parameters.environment, :debugging => parameters.debugging)
  end

  #geolocation ne doit pas être nil
  def proxy(geolocation)
    if !geolocation[:ip].nil? and !geolocation[:port].nil? and
        !geolocation[:user].nil? and !geolocation[:pwd].nil?
      type_proxy = :proxy_http_basic_authentication
      proxy = ["#{geolocation[:protocol]}://#{geolocation[:ip]}:#{geolocation[:port]}", geolocation[:user], geolocation[:pwd]]

    elsif !geolocation[:ip].nil? and !geolocation[:port].nil? and
        geolocation[:user].nil? and geolocation[:pwd].nil?
      type_proxy = :proxy
      proxy = "#{geolocation[:protocol]}://#{geolocation[:ip]}:#{geolocation[:port]}"

    else
      raise Error.new(BAD_GEOLOCATION, :values => {:geo => geolocation.to_s})
    end
    [type_proxy, proxy]
  end

  module_function :init_logging
  module_function :proxy
  module_function :scrape
  module_function :scrape_as_saas
  module_function :majestic_ident_authen

  class Backlink
    include Errors
    include Addressable


    INDEX_MAX = 5
    COUNT_THREAD = 10
    @logger = nil

    SEPARATOR = ";"

    attr_reader :url,
                :path,
                :title,
                :hostname,
                :is_a_backlink


    def initialize(url)
      raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "url"}) if url.nil? or url.empty?

      begin
        @url = url.strip
        @title = ""
        @is_a_backlink = false
        uri = URI.parse(@url)

      rescue Exception => e
        raise Error.new(BAD_URL_BACKLINK, :values => {:url => @url}, :error => e)

      else
        @path = uri.path
        @hostname = uri.hostname
        raise Error.new(BAD_URL_BACKLINK, :values => {:url => @url}, :error => e) if uri.scheme.nil? or
            uri.path.nil? or
            uri.hostname.nil?
      end
    end

    def to_s
      "#{@url} ; #{@is_a_backlink} ; #{@title}"
    end

    def evaluate(landing_url, geolocation)

      type_proxy = nil
      proxy = nil

      begin
        raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "landing_url"}) if landing_url.nil? or landing_url.empty?

        type_proxy, proxy = Backlinks::proxy(geolocation) unless geolocation == nil.to_json

        page = open(@url,
                    "User-Agent" => UserAgentRandomizer::UserAgent.fetch(type: "desktop_browser").string, # n'est pas obligatoire
                    type_proxy => proxy,
                    :ssl_verify_mode => OpenSSL::SSL::VERIFY_NONE).read if !type_proxy.nil? and !proxy.nil?

        page = open(@url,
                    "User-Agent" => UserAgentRandomizer::UserAgent.fetch(type: "desktop_browser").string, # n'est pas obligatoire
                    :ssl_verify_mode => OpenSSL::SSL::VERIFY_NONE).read if type_proxy.nil? and proxy.nil?

        @title = Nokogiri::HTML(page).css('title').text

        Nokogiri::HTML(page).css('a').each { |link|

          begin
            url_scrapped = link.attributes["href"].value

            uri_scrapped = URI.parse(url_scrapped)
            uri_landing = URI.parse(landing_url)

          rescue Exception => e

          else
            @is_a_backlink = uri_scrapped.hostname == uri_landing.hostname and
                ((uri_scrapped.path == "" and uri_landing.path == "/") or # pour pallier au cas où l'url scrapper est mal formée : manque '/' à la fin
                    uri_scrapped.path == uri_landing.path)

            break if @is_a_backlink

          end
        }
      rescue Exception => e
        raise Error.new(BACKLINK_NOT_EVALUATED, :values => {:url => @url}, :error => e)

      end
    end

    private

  end
end