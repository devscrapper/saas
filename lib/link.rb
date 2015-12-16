#encoding:utf-8
require 'net/http'
require 'nokogiri'
require 'domainatrix'
require 'addressable/uri'
require 'open-uri'
require 'yaml'
require 'json'
require 'user_agent_randomizer'
require_relative 'error'


module Links
  include Errors
  include Addressable
  LINKS_NOT_SCRAPED = 2000
  SCHEME_NOT_VALID = 2001
  NO_LIMIT = 0
  @logger = nil
  class Page
    include Errors
    include Addressable


    # attribut en input
    attr :url, # url de la page
         :document # le contenu de la page
    # attribut en output
    attr :title, # titre recuper� de la page html
         :body_not_html, # body non html de la page
         :body_html # body html de la page
    attr_reader :links # liens conserv�s de la page
    # attribut private
    attr :parsed_document, # le document pars� avec nokogiri
         :root_url, # url root du site d'o� provient la page
         :schemes # ensemble de schemes recherch�s dans une page


    def initialize(url, document)
      begin
        @links = []
        @url = url
        @document = document
        @parsed_document ||= Nokogiri::HTML(@document)
      rescue Exception => e
        raise Error.new(LINKS_NOT_SCRAPED, :values => {:url => @url}, :error => e)

      end
    end

    def to_json(*a)
      {
          'url' => @url,
          'title' => @title,
          'links' => @links,
      }.to_json(*a)
    end


    def title
      begin
        @title ||= @parsed_document.title() #.gsub(/\t|\n|\r/, ''), permet d'enlever ces caracteres
      rescue
        @title = ""
      end
    end

    # ---------------------------------------------------------------------------------------------------------------------
    # links (root_url, schemes, type)
    # ---------------------------------------------------------------------------------------------------------------------
    # INPUTS
    #   root_url : url de d�part
    #   schemes : Array de scheme des links � s�lectionner
    #       :http, :https, :file, :mailto, ...
    #   type : Array des type de liens � s�lectionner
    #       :local : liens du document dont leur host est celui du document
    #       :global : liens du document dont leur host est un sous-domaine du host du document
    #       :full : liens du documents qq soit leur host qui ne sont pas LOCAL, ni GLOBAL
    #        pour avoir tous les liens il faut specifier [LOCAL, GLOBAL, FULL]
    # ---------------------------------------------------------------------------------------------------------------------
    # OUTPUT
    # Array d'url absolue
    # ---------------------------------------------------------------------------------------------------------------------
    def extract_links(root_url = nil, count_link = NO_LIMIT, schemes = [:http], type = [:local, :global])
      @schemes = schemes
      uri = URI.parse(root_url)

      raise Error.new(SCHEME_NOT_VALID, :values => {:url => @url, :scheme => uri.scheme}) unless [:http, :https].include?(uri.scheme.to_sym)

      @root_url = "#{uri.scheme}://#{uri.host}:#{uri.port}/#{uri.path}/"
      @links = parsed_links.map { |l|
        begin
          abs_l = absolutify_url(unrelativize_url(l))
          # on ne conserve que les link qui r�pondent � la s�lection sur le
          abs_l if acceptable_scheme?(abs_l) and # scheme
              acceptable_link?(type, abs_l, @root_url) # le perim�tre : domaine, sous-domaine, hors du domaine
        rescue
        end
      }.compact
      # on retourne un nombre limite si besoin
      @links = @links[0..count_link - 1] if count_link != NO_LIMIT
      @links
    end

    # ces deux fonctions doivent rester en public sinon cela bug
    def acceptable_scheme?(l)
      @schemes.include?(URI.parse(l).scheme.to_sym) or @schemes.include?(URI.parse(l).scheme)
    end

    def acceptable_link?(type, l, r)
      # r : le host du site
      # l : le lien que l'on veut analyser
      r_host = URI.parse(r).host
      if r_host != "localhost"
        # on s'assure qu'on est pas sur un domain localhost car dominatrix ne fonctionne pas sans TLD (.fr)
        l = Domainatrix.parse(l)
        r = Domainatrix.parse(r)
        if l.subdomain == r.subdomain and
            l.domain == r.domain and
            l.public_suffix == r.public_suffix
          type.include?(:local) or type.include?("local")
        else
          if l.domain == r.domain and
              l.public_suffix == r.public_suffix
            type.include?(:global) or type.include?("global")
          else
            type.include?(:full) or type.include?("full")
          end
        end
      else
        if r_host == URI.parse(l).host
          type.include?(:local) or type.include?("local")
        else
          type.include?(:full)or type.include?("full")
        end
      end
    end

    # ---------------------------------------------------------------------------------------------------------------------
    # body(format = :html)
    # ---------------------------------------------------------------------------------------------------------------------
    # INPUTS
    # format : le type de restitution
    #         :text : sans les mots du langage html
    #         :html : avec les mots du langage html
    # ---------------------------------------------------------------------------------------------------------------------
    # OUTPUTS
    # le contenu de la balise body
    # ---------------------------------------------------------------------------------------------------------------------
    def body(format = :html)
      return @body_not_html ||= @parsed_document.search("//body").inner_text if format == :text
      @body_html ||= @parsed_document.search("//body").inner_html if format == :html
    end

    # ---------------------------------------------------------------------------------------------------------------------
    private

    def parsed_links
      begin
        @parsed_document.search("//a").map { |link|
          link.attributes["href"].to_s.strip
        }.uniq
      rescue
        []
      end
    end

    # Convert a relative url like "/users" to an absolute one like "http://example.com/users"
    # Respecting already absolute URLs like the ones starting with http:, ftp:, telnet:, mailto:, javascript: ...
    def absolutify_url(url)
      if url =~ /^\w*\:/i
        url
      else
        URI.parse(@root_url).merge(URI.encode(url)).to_s.gsub("%23", "#")
      end
    end

    # Convert a protocol-relative url to its full form, depending on the scheme of the page that contains it
    def unrelativize_url(url)
      url =~ /^\/\// ? "#{scheme}://#{url[2..-1]}" : url
    end


  end
# End Class Page ------------------------------------------------------------------------------------------------


#----------------------------------------------------------------------------------------------------------------
# scrape
#----------------------------------------------------------------------------------------------------------------
# fournit la liste des links de la page identifié par l'url
#----------------------------------------------------------------------------------------------------------------
# input :
# un domaine sans http
# une instance de webdriver

# en options :
# :geolocation = les propriétés d'une geolocation pour faire la requete
# :scraped_f = un nom et chemin absolue de fichier pour stocker les resultats
# :range = :selection (le couple [landing_link, keywords]) | :full (toutes les colonnes)
#
# output :
# par defaut :
# une String contenant toutes les données avec toutes les colonnes
#
# sinon un Array dont chaque occurence contient le couple [landing_link, keywords] par exemple ou d'autres colonnes
# sinon un File contenant toutes les données avec toutes les colonnes
# sinon un File dont chaque occurence contient le couple [landing_link, keywords] par exemple ou d'autres colonnes
#----------------------------------------------------------------------------------------------------------------
# si on capte un pb de deconnection du site semrush car le couple user/password s'est connecté à partir d'un autre
# navigateur alors on rejoue l'identi/authen (on capte une exception, on appelle semrush_ident_authen et on fait un retry)
#----------------------------------------------------------------------------------------------------------------
  def scrape(url, host, types, schemes, count, opts={})
    init_logging
    type_proxy = nil
    proxy = nil

    unless opts[:geolocation].nil?
      type_proxy, proxy = proxy(opts[:geolocation])
      @logger.an_event.debug "type proxy #{type_proxy}, proxy #{proxy}" if !type_proxy.nil? and !proxy.nil?
    end

    try_count = 3

    begin
      raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "url"}) if url.nil? or url.empty?
      raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "host"}) if host.nil? or host.empty?
      raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "types"}) if types.nil? or types.empty?
      raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "schemes"}) if schemes.nil? or schemes.empty?


      page = open(url,
                  "User-Agent" => UserAgentRandomizer::UserAgent.fetch(type: "desktop_browser").string, # n'est pas obligatoire
                  type_proxy => proxy,
                  :ssl_verify_mode => OpenSSL::SSL::VERIFY_NONE).read if !type_proxy.nil? and !proxy.nil?

      page = open(url,
                  "User-Agent" => UserAgentRandomizer::UserAgent.fetch(type: "desktop_browser").string, # n'est pas obligatoire
                  :ssl_verify_mode => OpenSSL::SSL::VERIFY_NONE).read if type_proxy.nil? and proxy.nil?


    rescue Exception => e
      sleep 5
      try_count -= 1
      retry if try_count > 0
      raise Error.new(LINKS_NOT_SCRAPED, :values => {:url => url}, :error => e)

    else
      scraped_page = Page.new(url, page)
      scraped_page.title()
      scraped_page.body(:text)
      scraped_page.extract_links(host, count, schemes, types)
      scraped_page

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


  module_function :proxy
  module_function :init_logging
  module_function :scrape


end