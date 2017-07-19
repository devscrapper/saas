#encoding:utf-8
require 'i18n'
require 'net/http'
require 'nokogiri'
require 'hpricot'
require 'addressable/uri'
require 'selenium-webdriver'
require 'csv'
require 'open-uri'
require 'thwait'
require 'yaml'
require 'json'
require_relative '../lib/parameter'
require_relative 'error'


module Keywords
  include Errors
  include Addressable
  ARGUMENT_NOT_DEFINE = 1500
  BAD_GEOLOCATION = 1501
  IDENTIFICATION_FAILED = 1502
  KEYWORD_NOT_SUGGESTED = 1503
  KEYWORD_NOT_EVALUATED = 1504
  CONNEXION_TO_SEMRUSH_LOOSE = 1505
  KEYWORD_NOT_SCRAPED = 1506
  WEBDRIVER_SUGGESTION_FAILED = 1507
  KEYWORD_NOT_FOUND = 1508
  SEMRUSH_SUBSCRIPTION_IS_OVER = 1509

  EOFLINE = "\n"
  SEPARATOR = ";"
  INDEX_MAX = 3
  ALPHABET = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z']
  @logger = nil
  class Keyword
    include Errors
    include Addressable


    attr_reader :words, #string of word
                :engines # hash contenant par engine l'url et l'index de la page dans laquelle le domain a été trouvé


    #----------------------------------------------------------------------------------------------------------------
    # sinitialize(words, url="", domain="", index="")
    #----------------------------------------------------------------------------------------------------------------
    # créé un objet Keyword :
    # - soit à partir d'une chaine validant la regexp
    # - soit à partir des valeurs du mot clé
    #----------------------------------------------------------------------------------------------------------------
    # input :
    # words : list de mots constituant le Keyword ou bien une chaine contenant une mise à plat sous format string au moyen
    # de self.to_s
    # url : l'url recherchée par les mots (mot issus semrush)
    # domain : le domain recherché par les mots (mots issus de Google Suggest)
    # index : list des index de page pour les engine pourlesques la recherche estun succes
    #----------------------------------------------------------------------------------------------------------------
    #----------------------------------------------------------------------------------------------------------------
    def initialize(words)
      raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "words"}) if words.nil? or words.empty?

      @words = words.strip
      @engines = {}
    end

    #----------------------------------------------------------------------------------------------------------------
    # evaluate(hostname, driver)
    #----------------------------------------------------------------------------------------------------------------
    # fournit la liste des mots cles d'un domaine au moyen de semrush.com
    #----------------------------------------------------------------------------------------------------------------
    # input :
    # un domaine sans http
    # une instance de webdriver
    # en options :
    # les propriétés d'une geolocation pou faire la requete
    # un nom absolu de fichier pour stocker les couples [landing_link, keywords] ; aucun tableau ne sera fournit en Output
    # output :
    # un tableau dont chaque occurence contient le couple [landing_link, keywords]
    # nom absolu de fichier passé en input contenant les données issues de semtush en l'état
    #----------------------------------------------------------------------------------------------------------------
    # si on capte un pb de deconnection du site semrush car le couple user/password s'est connecté à partir d'un autre
    # navigateur alors on rejoue l'identi/authen (on capte une exception, on appelle semrush_ident_authen et on fait un retry)
    #----------------------------------------------------------------------------------------------------------------

    #opts : contient soit un driver soit un proxy soit rien
    # si opts is_a(Hash) alors => proxy, les rquete http passe par un proxy
    # si opts n'est pas un hash => driver
    # si opts = nil => pas de proxy pour requete http
    def evaluate_link(domain, driver, geolocation=nil)
      raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "domain"}) if domain.nil? or domain.empty?

      begin
        google = Thread.new { Thread.current["name"] = :google; search_google(INDEX_MAX, domain, :link, driver) }
        yahoo = Thread.new { Thread.current["name"] = :yahoo; search_yahoo(INDEX_MAX, domain, geolocation) }
        bing = Thread.new { Thread.current["name"] = :bing; search_bing(INDEX_MAX, domain, geolocation) }

        #google.abort_on_exception = true
        #yahoo.abort_on_exception = true
        #bing.abort_on_exception = true

        #ThreadsWait.all_waits(google) do |t|
        ThreadsWait.all_waits(google, yahoo, bing) do |t|

        end
      rescue Exception => e
        raise Error.new(KEYWORD_NOT_EVALUATED, :values => {:variable => "domain"}, :error => e)

      end
    end

    def evaluate_sea(domain, driver, geolocation=nil)
      raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "domain"}) if domain.nil? or domain.empty?

      begin
        search_google(INDEX_MAX, domain, :sea, driver)

      rescue Exception => e
        raise Error.new(KEYWORD_NOT_EVALUATED, :values => {:variable => "domain"}, :error => e)

      end
    end

    def evaluate_as_saas(domain)
      try_count = 3

      begin
        parameters = Parameter.new(__FILE__)
        saas_host = parameters.saas_host.to_s
        saas_port = parameters.saas_port.to_s
        time_out = parameters.time_out_saas_evaluate.to_i
        raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "domain"}) if domain.nil? or domain.empty?
        raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "saas_host"}) if saas_host.nil? or saas_host.empty?
        raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "saas_port"}) if saas_port.nil? or saas_port.empty?
        raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "time_out_saas_evaluate"}) if time_out.nil? or time_out == 0


        #query http vers keywords saas
        href = "http://#{saas_host}:#{saas_port}/?action=evaluate&keywords=#{@words}&domain=#{domain}"

        keywords_io = open(href,
                           "r:utf-8",
                           {:read_timeout => time_out})

      rescue Exception => e
        sleep 5
        try_count -= 1
        retry if try_count > 0
        raise Error.new(KEYWORD_NOT_EVALUATED, :values => {:keyword => @words}, :error => e)

      else
        @engines = JSON.parse(keywords_io.string)

      end

    end

    #----------------------------------------------------------------------------------------------------------------
    # search(keywords, driver)
    #----------------------------------------------------------------------------------------------------------------
    # fournit la liste des resultats de recherche à partir des mot clé
    #----------------------------------------------------------------------------------------------------------------
    # input :
    # mots clé
    # en options :
    # les propriétés d'une geolocation pou faire la requete
    # un nom absolu de fichier pour stocker les couples [landing_link, keywords] ; aucun tableau ne sera fournit en Output
    # output :
    # un tableau dont chaque occurence contient le couple [landing_link, keywords]
    # nom absolu de fichier passé en input contenant les données issues de semtush en l'état
    #----------------------------------------------------------------------------------------------------------------
    #----------------------------------------------------------------------------------------------------------------

    #opts : contient soit un driver soit un proxy soit rien
    # si opts is_a(Hash) alors => proxy, les rquete http passe par un proxy
    # si opts n'est pas un hash => driver
    # si opts = nil => pas de proxy pour requete http
    def search(index, count_pages, driver, geolocation=nil)
      begin
        google = Thread.new { Thread.current["name"] = :google; search_google(count_pages, nil, :link, driver) }
        yahoo = Thread.new { Thread.current["name"] = :yahoo; search_yahoo(count_pages, nil, geolocation) }
        bing = Thread.new { Thread.current["name"] = :bing; search_bing(count_pages, nil, geolocation) }

        #google.abort_on_exception = true
        #yahoo.abort_on_exception = true
        #bing.abort_on_exception = true

        #ThreadsWait.all_waits(google) do |t|
        ThreadsWait.all_waits(google, yahoo, bing) do |t|

        end
      rescue Exception => e
        raise Error.new(KEYWORD_NOT_EVALUATED, :values => {:variable => "domain"}, :error => e)

      end
    end

    #----------------------------------------------------------------------------------------------------------------
    # google_suggest(hostname, driver)
    #----------------------------------------------------------------------------------------------------------------
    # fournit la liste des mots cles d'un domaine au moyen de semrush.com
    #----------------------------------------------------------------------------------------------------------------
    # input :
    # un domaine sans http
    # une instance de webdriver
    # en options :
    # les propriétés d'une geolocation pou faire la requete
    # un nom absolu de fichier pour stocker les couples [landing_link, keywords] ; aucun tableau ne sera fournit en Output
    # output :
    # un tableau dont chaque occurence contient le couple [landing_link, keywords]
    # nom absolu de fichier passé en input contenant les données issues de semtush en l'état
    #----------------------------------------------------------------------------------------------------------------
    # si on capte un pb de deconnection du site semrush car le couple user/password s'est connecté à partir d'un autre
    # navigateur alors on rejoue l'identi/authen (on capte une exception, on appelle semrush_ident_authen et on fait un retry)
    #----------------------------------------------------------------------------------------------------------------
    def suggest_google(driver, prefixe ="")
      raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "driver"}) if driver.nil?
      suggesteds = []


      begin
        driver.navigate_to "https://www.google.fr/"
        element = driver.find_element(:name, 'q')
        element.clear
        element.send_keys "#{@words} #{prefixe}"

      rescue Exception => e
        raise Error.new(WEBDRIVER_SUGGESTION_FAILED, :values => {:engine => "google"}, :error => e)

      else
        sleep 1
        suggesteds = Nokogiri::HTML(driver.page_source).css('div.sbqs_c').map { |suggested|
          suggested.text.gsub("\u00A0", " ")
        }
        I18n.enforce_available_locales = false
        suggesteds += Nokogiri::HTML(driver.page_source).css('div.gspr_a').map { |suggested|
          #suppression des espaces insécables
          kw = suggested.text.gsub("\u00A0", " ")
          #suppression des accents pour s'assurer que les  words ne sont pas présents dans suggested
          unless I18n.transliterate(kw).include?(I18n.transliterate(@words))
            "#{@words} #{kw}"
          else
            kw
          end

        }

      ensure
        suggesteds

      end
    end


    def suggest_bing(driver, prefixe ="")
      raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "driver"}) if driver.nil?
      suggesteds = []
      begin
        driver.navigate_to "http://www.bing.com/?cc=fr"
        element = driver.find_element(:name, 'q')
        element.clear
        element.send_keys "#{@words} #{prefixe}"

      rescue Exception => e
        raise Error.new(WEBDRIVER_SUGGESTION_FAILED, :values => {:engine => "bing"}, :error => e)

      else
        sleep 1
        suggesteds = Nokogiri::HTML(driver.page_source).css('div.sa_tm').map { |suggested| suggested.text }

      ensure
        suggesteds

      end
    end

    def suggest_yahoo(driver, prefixe ="")
      raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "driver"}) if driver.nil?

      suggesteds = []
      begin
        driver.navigate_to "https://fr.search.yahoo.com/"
        element = driver.find_element(:name, 'p')
        element.clear
        element.send_keys "#{@words} #{prefixe}"

      rescue Exception => e
        raise Error.new(WEBDRIVER_SUGGESTION_FAILED, :values => {:engine => "yahoo"}, :error => e)

      else
        sleep 3
        suggesteds += Nokogiri::HTML(driver.page_source).css('ul.sa-tray-list-container > li').map { |suggested|
          URI.unencode(suggested.attributes['data'].value)
        }

      ensure
        suggesteds

      end
    end


    def to_s
      s = "#{@words} "
      s += engines.to_s
      s
    end

    private

    def search_bing(max_count_page, domain=nil, geolocation)
      url = "http://www.bing.com/search?q=#{URI.encode(@words)}"
      type_proxy = nil
      proxy = nil
      found = false

      begin
        raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "max_count_page"}) if max_count_page.nil?
        #raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "domain"}) if domain.nil? or domain.empty?

        type_proxy, proxy = Keywords::proxy(geolocation) unless geolocation == nil.to_json

        max_count_page.times { |index_page|
          sleep [*5..20].sample

          page = open(url,
                      "User-Agent" => UserAgentRandomizer::UserAgent.fetch(type: "desktop_browser").string, # n'est pas obligatoire
                      type_proxy => proxy,
                      :ssl_verify_mode => OpenSSL::SSL::VERIFY_NONE).read if !type_proxy.nil? and !proxy.nil?

          page = open(url,
                      "User-Agent" => UserAgentRandomizer::UserAgent.fetch(type: "desktop_browser").string, # n'est pas obligatoire
                      :ssl_verify_mode => OpenSSL::SSL::VERIFY_NONE).read if type_proxy.nil? and proxy.nil?


          Nokogiri::HTML(page).css('h2 > a').each { |link|


            begin
              url_scrapped = link.attributes["href"].value
              uri_scrapped = URI.parse(url_scrapped)

            rescue Exception => e

            else
              unless domain.nil?
                found = uri_scrapped.hostname.include?(domain) unless uri_scrapped.hostname.nil?

                if found
                  @engines.merge!({:bing => {:url => url_scrapped, :index => index_page + 1}})
                  break
                end

              else
                @engines.merge!({:bing => {:url => url_scrapped, :index => index_page + 1}})

              end
            end
          }
          #recherche du lien "Suivant"  pour passer à la page suivante
          nxt = Nokogiri::HTML(page).css('a.sb_pagN').first

          # passe à la page suivante
          if !found and index_page < max_count_page - 1 and !nxt.nil?
            url = "http://www.bing.com#{nxt.attributes["href"].value}"

          else
            #on a terminé :
            # soit parce qu'on a trouvé l'url ou une url contenant le domain du website
            # soit pas d'url repondant au critere et le nombre de page max de recherche est dépassé
            #si l'url ou une url contenant le domain du website a été trouvée on arrete de chercher
            break

          end
        }
      rescue Exception => e
        raise Error.new(KEYWORD_NOT_FOUND, :values => {:keyword => @words, :engine => "bing"}, :error => e)

      else
      ensure

      end
    end

    def search_google_old(max_count_page, domain, geolocation)
      url = "https://www.google.fr/search?q=#{URI.encode(@words)}"
      type_proxy = nil
      proxy = nil
      found = false

      begin
        raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "max_count_page"}) if max_count_page.nil?
        raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "domain"}) if domain.nil? or domain.empty?

        type_proxy, proxy = Keywords::proxy(geolocation) unless geolocation == nil.to_json


        sleep [*15..20].sample

        cookie = (page = open("https://www.google.fr/",
                              "User-Agent" => UserAgentRandomizer::UserAgent.fetch(type: "desktop_browser").string, # n'est pas obligatoire
                              type_proxy => proxy,
                              :ssl_verify_mode => OpenSSL::SSL::VERIFY_NONE)).meta["set-cookie"] if !type_proxy.nil? and !proxy.nil?
        cookie = (page = open("https://www.google.fr/",
                              "User-Agent" => "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:33.0) Gecko/20100101 Firefox/33.0",
                              :ssl_verify_mode => OpenSSL::SSL::VERIFY_NONE)).meta["set-cookie"] if type_proxy.nil? and proxy.nil?

        max_count_page.times { |index_page|

          page = open(url,
                      "Cookie" => cookie,
                      "User-Agent" => UserAgentRandomizer::UserAgent.fetch(type: "desktop_browser").string, # n'est pas obligatoire
                      type_proxy => proxy,
                      :ssl_verify_mode => OpenSSL::SSL::VERIFY_NONE).read if !type_proxy.nil? and !proxy.nil?

          page = open(url,
                      "Cookie" => cookie,
                      "User-Agent" => UserAgentRandomizer::UserAgent.fetch(type: "desktop_browser").string, # n'est pas obligatoire
                      :ssl_verify_mode => OpenSSL::SSL::VERIFY_NONE).read if type_proxy.nil? and proxy.nil?


          Nokogiri::HTML(page).css('h3.r > a').each { |link|
            begin
              # soit la landing url est = link
              # soit le domain du website appartient (sous chaine) d'un link
              url_scrapped = link.attributes["href"].value


              uri_scrapped = URI.parse(url_scrapped)

            rescue Exception => e

            else
              found = uri_scrapped.hostname.include?(domain) unless uri_scrapped.hostname.nil?

              if found
                @engines.merge!({:google => {:url => url_scrapped, :index => index_page + 1}})
                break
              end

            end
          }

          nxt = Nokogiri::HTML(page).css('a#pnnext.pn').first

          if !found and index_page < max_count_page - 1 and !nxt.nil?
            url = "https://www.google.fr#{nxt.attributes["href"].value}"

          else
            break

          end

        }
      rescue Exception => e
        raise Error.new(KEYWORD_NOT_FOUND, :values => {:keyword => @words, :engine => "google"}, :error => e)

      else

      ensure

      end
    end

    def search_google(max_count_page, domain=nil, type, driver)
      url = "https://www.google.fr/search?q=#{URI.encode(@words)}"
      type_proxy = nil
      proxy = nil
      found = false

      begin
        raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "max_count_page"}) if max_count_page.nil?
        #raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "domain"}) if domain.nil? or domain.empty?
        raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "type"}) if type.nil? or type.empty?
        raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "driver"}) if driver.nil?

        case type
          when :link # recherche les link
            element_css = 'h3.r > a'
          when :sea # recherche les Adsense
            element_css = 'ol > li.ads-ad > h3 > a:nth-child(2)'
        end

        driver.navigate_to "https://www.google.fr/"
        element = driver.find_element(:name, 'q')
        element.clear
        element.send_keys "#{@words}"
        element.submit

      rescue Exception => e
        raise Error.new(KEYWORD_NOT_FOUND, :values => {:keyword => @words, :engine => "google"}, :error => e)

      else

        max_count_page.times { |index_page|

          driver.find_elements(:css, element_css).each { |link|
            unless domain.nil?
              begin

                # soit la landing url est = link
                # soit le domain du website appartient (sous chaine) d'un link
                url_scrapped = link["href"]
                uri_scrapped = URI.parse(url_scrapped)

              rescue Exception => e

              else
                found = uri_scrapped.hostname.include?(domain) unless uri_scrapped.hostname.nil?
                p "page #{index_page + 1} : #{uri_scrapped} : domain found ? #{found}"
                if found
                  @engines.merge!({:google => {:url => url_scrapped, :index => index_page + 1}})
                  break
                end

              end

            else
              p "page #{index_page + 1} : #{link["href"]}"
              @engines.merge!({:google => {:url => link["href"], :index => index_page + 1}})

            end
          }

          nxt = driver.find_element(:css, 'a#pnnext.pn')

          if !found and index_page <= max_count_page - 1 and !nxt.nil?
            nxt.click
            sleep 2 # necessaire pour eviter de passer trop vite de page en page car sinon il ne detecte pas les lien ; hum hum , empirique et valuable testing
          else
            break

          end

        }

      ensure
        driver.clear_cookies
      end
    end

    def search_yahoo(max_count_page, domain=nil, geolocation)
      url = "https://fr.search.yahoo.com/search?p=#{URI.encode(@words)}"
      type_proxy = nil
      proxy = nil
      found = false

      url_scrapped = ""
      begin
        raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "max_count_page"}) if max_count_page.nil?
        #raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "domain"}) if domain.nil? or domain.empty?

        type_proxy, proxy = Keywords::proxy(geolocation) unless geolocation == nil.to_json

        max_count_page.times { |index_page|
          sleep [*5..20].sample

          page = open(url,
                      "User-Agent" => "Mozilla/5.0 (Windows NT 6.1; WOW64; rv:33.0) Gecko/20100101 Firefox/33.0",
                      type_proxy => proxy,
                      :ssl_verify_mode => OpenSSL::SSL::VERIFY_NONE).read if !type_proxy.nil? and !proxy.nil?
          page = open(url,
                      "User-Agent" => UserAgentRandomizer::UserAgent.fetch(type: "desktop_browser").string,
                      :ssl_verify_mode => OpenSSL::SSL::VERIFY_NONE).read if type_proxy.nil? and proxy.nil?

          Nokogiri::HTML(page).css('h3 > a.yschttl.spt').each { |link|
            # soit la landing url est = link
            # soit le domain du website appartient (sous chaine) d'un link
            begin
              uri = URI.parse(link.attributes["href"].value)
            rescue Exception => e
            else
              begin
                # url extrait de la page de resultat courante
                url_scrapped =/\/RU=(?<href>.+)\/RK=/.match(URI.unencode(uri.path))[:href]
                uri_scrapped = URI.parse(url_scrapped)

              rescue Exception => e

              else
                unless domain.nil?
                  found = uri_scrapped.hostname.include?(domain)

                  if found
                    @engines.merge!({:yahoo => {:url => url_scrapped, :index => index_page + 1}})

                    break
                  end
                else
                  @engines.merge!({:yahoo => {:url => url_scrapped, :index => index_page + 1}})

                end
              end
            end

          }
          #recherche du lien "Suivant"  pour passer à la page suivante
          nxt = Nokogiri::HTML(page).css('a#pg-next').first

          # passe à la page suivante
          if !found and index_page <= max_count_page - 1 and !nxt.nil?
            url = nxt.attributes["href"].value

          else
            #on a terminé :
            # soit parce qu'on a trouvé l'url ou une url contenant le domain du website
            # soit pas d'url repondant au critere et le nombre de page max de recherche est dépassé
            break

          end
        }
      rescue Exception => e
        raise Error.new(KEYWORD_NOT_FOUND, :values => {:keyword => @words, :engine => "yahoo"}, :error => e)

      else
      ensure

      end
    end


  end

#----------------------------------------------------------------------------------------------------------------
# semrush_ident_authen(driver)
#----------------------------------------------------------------------------------------------------------------
# accede au site web semrush et i'dentifie le user du fichier de parametre
#----------------------------------------------------------------------------------------------------------------
# input :
# un driver, un instance de selenium-webdriver
# output :
# RAS
# exception :
# NOT_IDENTIFY_SEMRUSH
#----------------------------------------------------------------------------------------------------------------
#----------------------------------------------------------------------------------------------------------------
  def semrush_ident_authen(driver)
    init_logging

    begin
      parameters = Parameter.new(__FILE__)
      user = parameters.semrush_user.to_s
      pwd = parameters.semrush_pwd.to_s


      raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "user"}) if user.empty? or user.nil?
      raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "pwd"}) if pwd.empty? or pwd.nil?


      driver.navigate_to "http://fr.semrush.com/fr/"; @logger.an_event.debug "navigate to #{driver.current_url}"
      #@logger.an_event.debug "page source of url #{driver.current_url} : #{driver.page_source}"
      driver.one_element_is_present([[:css, "button.js-authentication-login.s-btn.-xs.-success"],
                                     [:css, "button.btn.btn_brand"],
                                     [:css, "i.s-icon.-s.-enter"]]).click

      email = driver.one_element_is_present([[:css, "form.sem-login-form > div.sem-field-group > div.sem-input-field.icon-left > input[name='email']"], [:css, "input.auth-form__input"]])
      #  email = driver.is_element_present(:css, "") || driver.is_element_present(:css, "input.auth-form__input")
      email.clear
      email.send_keys user; @logger.an_event.debug "set input[name='email'] by #{user}"
      #password = driver.find_element(:css, "form.sem-login-form > div.sem-field-group > div.sem-input-field.icon-left > input[name='password']")
      password = driver.one_element_is_present([[:css, "form.sem-login-form > div.sem-field-group > div.sem-input-field.icon-left > input[name='password']"], [:css, "input.auth-form__input.-forgot"]])
      #  driver.is_element_present(:css, "form.sem-login-form > div.sem-field-group > div.sem-input-field.icon-left > input[name='password']") || driver.is_element_present(:css, "input.auth-form__input.-forgot")
      password.clear
      password.send_keys pwd; @logger.an_event.debug "set input[name='password'] by #{pwd}"

      # checkbox =  driver.one_element_is_present([[:id, "login-remember"], [:css, "input.auth-form__input.-forgot"]])

      # checkbox = driver.find_element(:id, 'login-remember')
      # checkbox.click; @logger.an_event.debug "click on login-remember"

      button = driver.one_element_is_present([[:xpath, "(//button[@value='Login'])[2]"], [:css, "button.s-btn.-m.-success.auth-form__button"]])
      #  button = driver.find_element(:xpath, "(//button[@value='Login'])[2]")
      button.submit; @logger.an_event.debug "submit signin"

    rescue Exception => e
      @logger.an_event.debug "page source of url #{driver.current_url} : #{driver.page_source}"
      raise Error.new(IDENTIFICATION_FAILED, :values => {:user => user}, :error => e)

    else
      sleep(5)
    ensure

    end
  end

#----------------------------------------------------------------------------------------------------------------
# scrape(hostname, driver)
#----------------------------------------------------------------------------------------------------------------
# fournit la liste des mots cles d'un domaine au moyen de semrush.com
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
  def scrape(hostname, driver, opts={})
    init_logging
    #"www.epilation-laser-definitive.info"
    type_proxy = nil
    proxy = nil
    keywords = ""
    keywords_io = nil

    unless opts[:geolocation].nil?
      type_proxy, proxy = proxy(opts[:geolocation])
      @logger.an_event.debug "type proxy #{type_proxy}, proxy #{proxy}" if !type_proxy.nil? and !proxy.nil?
    end

    keywords_f = opts.fetch(:scraped_f, nil)
    @logger.an_event.debug "keywords flow #{keywords_f}"

    range = opts.fetch(:range, :full)
    @logger.an_event.debug "range data #{range}"


    begin
      raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "hostname"}) if hostname.nil? or hostname.empty?
      raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "driver"}) if driver.nil?


      driver.navigate_to "http://fr.semrush.com/fr/info/#{hostname}?db=fr" unless driver.current_url == "https://fr.semrush.com/fr/info/#{hostname}?db=fr"

    rescue Error => e
      if e.code == Webscrapers::PAGE_NOT_FULL_LOAD
        # la page n'est pas completement chargé. peut être que le bouton <exporté> est disponible.
        #donc on ne lève pas d'erreur et on teste si le bton est présent

      else
        raise Error.new(KEYWORD_NOT_SCRAPED, :values => {:hostname => hostname}, :error => e)

      end

        #survient quand une connection a été réalisée simultanement à partir d'un autre navigateur
    rescue Selenium::WebDriver::Error::NoSuchElementError => e
      raise Error.new(CONNEXION_TO_SEMRUSH_LOOSE, :error => e) if driver.find_element(:css, 'div.sem-popup-body').displayed?

    rescue Exception => e
      if e.message.index("redirection forbidden:") == 0
        raise Error.new(SEMRUSH_SUBSCRIPTION_IS_OVER, :error => e)

      else
        raise Error.new(KEYWORD_NOT_SCRAPED, :values => {:hostname => hostname}, :error => e)

      end
    end

    begin

      element = driver.is_element_present(:css, "div.sem-reports-padding.sem-report.sem-keyword-overview > div.summary-not-found-block > div.summary-not-found > h2")

    rescue Exception => e

    end

    if element.nil? #pas trouver le texte "Sorry, we haven't found any information related to your request in the google.fr database."
      begin
        ##CompetitorsOrganicSearch > div.sem-widget-footer.clearfix > div.sem-widget-footer-rb.sem-widget-footer-export-links >
        driver.find_element(:link, "Exporter").click
        @logger.an_event.debug "click on Exporter"

        element = driver.find_element(:css, "a.export-block-icon-link.export-block-icon-csv")
        href = element.attribute('href')
        @logger.an_event.debug "uri keywords csv file semrush : #{href}"

        if !type_proxy.nil? and !proxy.nil?
          keywords_io = open(href,
                             "User-Agent" => driver.user_agent, # n'est pas obligatoire
                             type_proxy => proxy)
          @logger.an_event.debug "with proxy #{proxy} keywords csv file semrush downloaded #{keywords.to_yaml}"

        else
          keywords_io = open(href,
                             "User-Agent" => driver.user_agent)
          @logger.an_event.debug "keywords csv file semrush downloaded #{keywords.to_yaml}"

        end

      rescue Exception => e
        raise Error.new(KEYWORD_NOT_SCRAPED, :values => {:hostname => hostname}, :error => e)


      else
        if keywords_f.nil?
          keywords = keywords_io.read
          @logger.an_event.debug "lecture du fichier csv et rangement dans string"
          if range == :full
            #String
            # tout le contenu
            keywords

          else
            #Array
            #select url & keywords colonne
            keywords_arr = []

            CSV.parse(keywords,
                      {headers: true,
                       converters: :numeric,
                       header_converters: :symbol}).each { |row|
              keywords_arr << [row[:url], row[:keyword]]
            }
            keywords_arr
          end
        else

          if range == :full
            #File
            FileUtils.cp(keywords_io,
                         keywords_f)
            @logger.an_event.debug "copy du fichier csv dans flow #{keywords_f}"

          else
            #File
            #select url & keywords colonne
            keywords_f = File.open(keywords_f, "w+:bom|utf-8")
            CSV.open(keywords_io,
                     "r:bom|utf-8",
                     {headers: true,
                      converters: :numeric,
                      header_converters: :symbol}).map.each { |row|
              keywords_f.write("#{[row[:url], row[:keyword]].join(SEPARATOR1)}#{EOFLINE}")
            }
          end


        end

      ensure


      end
    else
      []
    end

  end

#keywords_file is absolute path file flow
  def scrape_as_saas(hostname, opts={})
    init_logging
    #"www.epilation-laser-definitive.info"
    type_proxy = nil
    proxy = nil
    keywords = ""
    keywords_io = nil

    keywords_f = opts.fetch(:scraped_f, nil)
    @logger.an_event.debug "keywords flow #{keywords_f}"

    range = opts.fetch(:range, :full)
    @logger.an_event.debug "range data #{range}"


    try_count = 3
    begin
      parameters = Parameter.new(__FILE__)
      saas_host = parameters.saas_host.to_s
      saas_port = parameters.saas_port.to_s
      time_out = parameters.time_out_saas_scrape.to_i

      raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "hostname"}) if hostname.nil? or hostname.empty?
      raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "saas_host"}) if saas_host.nil? or saas_host.empty?
      raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "saas_port"}) if saas_port.nil? or saas_port.empty?
      raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "time_out_saas_scrape"}) if time_out.nil? or time_out == 0

      #query http vers keywords saas
      href = "http://#{saas_host}:#{saas_port}/?action=scrape&hostname=#{hostname}"
      @logger.an_event.debug "uri scrape_saas : #{href}"

      keywords_io = open(href,
                         "r:utf-8",
                         {:read_timeout => time_out})

    rescue Exception => e
      @logger.an_event.warn "scrape keywords as saas for #{hostname} : #{e.message}"
      sleep 5
      try_count -= 1
      retry if try_count > 0
      @logger.an_event.error "scrape keywords as saas for #{hostname} : #{e.message}"
      raise Error.new(KEYWORD_NOT_SCRAPED, :values => {:hostname => hostname}, :error => e)

    else
      if keywords_f.nil?
        keywords = keywords_io.read
        @logger.an_event.debug "lecture du fichier csv et rangement dans string"
        if range == :full
          #String
          # tout le contenu
          keywords

        else
          #Array
          #select url & keywords colonne
          keywords_arr = []

          CSV.parse(keywords,
                    {headers: true,
                     converters: :numeric,
                     header_converters: :symbol}).each { |row|
            keywords_arr << [row[:url], row[:keyword]] if !row[:url].nil? and !row[:keyword].nil?
          }
          keywords_arr
        end
      else

        if range == :full
          #File
          FileUtils.cp(keywords_io,
                       keywords_f)
          @logger.an_event.debug "copy du fichier csv dans flow #{keywords_f}"

        else
          #File
          #select url & keywords colonne
          keywords_f = File.open(keywords_f, "w+:bom|utf-8")
          CSV.open(keywords_io,
                   "r:bom|utf-8",
                   {headers: true,
                    converters: :numeric,
                    header_converters: :symbol}).map.each { |row|
            keywords_f.write("#{[row[:url], row[:keyword]].join(SEPARATOR)}#{EOFLINE}")
          }
        end


      end

    ensure


    end
  end

#----------------------------------------------------------------------------------------------------------------
# suggest(engine, keyword, domain, driver)
#----------------------------------------------------------------------------------------------------------------
# fournit la liste des suggestions d'un mot clé pour une engine
#----------------------------------------------------------------------------------------------------------------
# input :
# un moteur de recherche
# un mot clé
# un domaine sans http
# une instance de webdriver
# en options :
# un nom absolu de fichier pour stocker les couples [landing_link, keywords] ; aucun tableau ne sera fournit en Output
# output :
# un tableau dont chaque occurence contient le couple [landing_link, keywords]
# nom absolu de fichier passé en input contenant les données issues de semtush en l'état
#----------------------------------------------------------------------------------------------------------------
# soit on retourne un tableau de mot clé, soit un flow conte
#----------------------------------------------------------------------------------------------------------------
  def suggest(keyword, driver)
    init_logging

    raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "keywords"}) if keyword.nil? or keyword.empty?
    raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "google_driver"}) if driver.nil?


    suggesteds = []

    kw = Keyword.new(keyword)

    begin

      suggesteds += kw.suggest_google(driver)
      driver.clear_cookies
      suggesteds += kw.suggest_yahoo(driver)
      driver.clear_cookies
      suggesteds += kw.suggest_bing(driver)
      driver.clear_cookies

      suggesteds.uniq!

      ALPHABET.sample(10).each { |a| # si temps de traitement est trop long alors on selectionne un sample de lettre
        kw = Keyword.new(keyword)

        suggesteds += kw.suggest_google(driver, a)
        driver.clear_cookies
        suggesteds += kw.suggest_yahoo(driver, a)
        driver.clear_cookies
        suggesteds += kw.suggest_bing(driver, a)
        driver.clear_cookies

        suggesteds.uniq!
      }

    rescue Error => e
      case e.code
        when WEBDRIVER_SUGGESTION_FAILED
          raise e

        else
          raise Error.new(KEYWORD_NOT_SUGGESTED, :values => {:keyword => keyword}, :error => e)

      end

    rescue Exception => e
      raise Error.new(KEYWORD_NOT_SUGGESTED, :values => {:keyword => keyword}, :error => e)

    else
      suggesteds

    end


  end

#----------------------------------------------------------------------------------------------------------------
# suggest(engine, keyword, domain, driver)
#----------------------------------------------------------------------------------------------------------------
# fournit la liste des suggestions d'un mot clé pour une engine
#----------------------------------------------------------------------------------------------------------------
# input :
# un moteur de recherche
# un mot clé
# un domaine sans http
# une instance de webdriver
# en options :
# un nom absolu de fichier pour stocker les couples [landing_link, keywords] ; aucun tableau ne sera fournit en Output
# output :
# un tableau dont chaque occurence contient le couple [landing_link, keywords]
# nom absolu de fichier passé en input contenant les données issues de semtush en l'état
#----------------------------------------------------------------------------------------------------------------
# soit on retourne un tableau de mot clé, soit un flow conte
#----------------------------------------------------------------------------------------------------------------
  def suggest_as_saas(keyword)
    init_logging


    try_count = 3
    suggesteds = []
    begin
      parameters = Parameter.new(__FILE__)
      saas_host = parameters.saas_host.to_s
      saas_port = parameters.saas_port.to_s
      time_out = parameters.time_out_saas_suggest.to_i
      raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "keywords"}) if keyword.nil? or keyword.empty?
      raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "saas_host"}) if saas_host.nil? or saas_host.empty?
      raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "saas_port"}) if saas_port.nil? or saas_port.empty?
      raise Error.new(ARGUMENT_NOT_DEFINE, :values => {:variable => "time_out_saas_suggest"}) if time_out.nil? or time_out == 0


      #query http vers keywords saas
      href = "http://#{saas_host}:#{saas_port}/?action=suggest&keywords=#{keyword}"
      @logger.an_event.debug "uri suggest_saas : #{href}"

      keywords_io = open(href,
                         "r:utf-8",
                         {:read_timeout => time_out})

    rescue Exception => e
      @logger.an_event.warn "suggest keywords as saas for #{keyword} : #{e.message}"
      sleep 5
      try_count -= 1
      retry if try_count > 0
      @logger.an_event.error "suggest keywords as saas for #{keyword} : #{e.message}"
      raise Error.new(KEYWORD_NOT_SUGGESTED, :values => {:hostname => keyword}, :error => e)
      suggesteds

    else
      suggesteds = JSON.parse(keywords_io.string)
      @logger.an_event.debug "suggested keywords as saas for #{keyword} : #{suggesteds}"

      suggesteds
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
  module_function :semrush_ident_authen
  module_function :scrape
  module_function :scrape_as_saas
  module_function :suggest_as_saas
  module_function :suggest


end