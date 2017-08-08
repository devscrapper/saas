require 'selenium-webdriver'
require_relative '../error'


module Webscrapers
  include Errors
  NAVIGATE_FAILED = 1403
  URL_UNREACHABLE = 1404
  ELEMENT_NOT_FOUND = 1405
  DRIVER_NOT_START = 1406
  NONE_ELEMENT_NOT_FOUND = 1407
  UNKNOWN_OS = 1408
  NO_FREE_PHANTOMJS = 1409
  PHANTOMJS_NOT_START = 1410
  XVFB_NOT_START = 1411
  FIREFOX_NOT_START = 1412
  DRIVER_NOT_STOP = 1413
  PAGE_NOT_FULL_LOAD = 1414


  class Webscraper
    include Errors


    TMP = File.expand_path(File.join("..", "..", "..", "tmp"), __FILE__)

    attr_reader :driver #instance de webdriver selenium avec phantomjs ou firefox

    attr :geolocation, #decrit les paramètres du proxy de geolocation
         :user_agent, #si gui | (headless & xvfb) alors la valeur est recuperée du webdriver lors du start du browser ff
         # si headless & phantomjs alors  la valeur est calculée aléatoirement avec 'user_agent_randomizer'
         :path_firefox #path du runtime de firefox

    def initialize(geolocation)
      @geolocation = geolocation unless geolocation.nil?
    end

    #
    # Delete all cookies
    #
    def clear_cookies
      @driver.manage.delete_all_cookies
    end

    def current_url
      @driver.current_url
    end

    #return element si présent, sinon nil
    def is_element_present(how, what)
      # wait = @driver.manage.timeouts.implicit_wait
      # @driver.manage.timeouts.implicit_wait = 0
      #
      result = find_elements(how, what).size() > 0 ? find_element(how, what) : nil
      #  @driver.manage.timeouts.implicit_wait = wait
      result
    end

    #tableau de couple how et what : [[how, what], ...]
    # retourne le premier element qui est présent
    def one_element_is_present(arr)
      element = nil
      arr.each { |e|
        element = is_element_present(e[0], e[1])
        break unless element.nil?
      }
      if element.nil?
        take_screenshot
        raise Error.new(NONE_ELEMENT_NOT_FOUND)
      end
      element

    end


    def find_element(how, what)
      begin
        @driver.find_element(how, what)

      rescue Exception => e
        take_screenshot
        raise Error.new(ELEMENT_NOT_FOUND, :values => {:element => what}, :error => e)

      end
    end

    def find_elements(how, what)
      begin
        @driver.find_elements(how, what)

      rescue Exception => e
        take_screenshot
        raise Error.new(ELEMENT_NOT_FOUND, :values => {:element => what}, :error => e)

      end
    end

    def manage
      @driver.manage
    end


    def page_source
      @driver.page_source
    end

    def restart
      stop
      start
    end


    private
    #demarre une instance de webdriver/firefox
    def start_firefox
      begin
        profile = Selenium::WebDriver::Firefox::Profile.new

        if @geolocation.nil?
          # pas de geolocation
          profile['network.proxy.type'] = 0
          profile['network.proxy.no_proxies_on'] = ""
        else
          #geolocation
          profile['network.proxy.type'] = 1
          case @geolocation.protocol
            when "http"
              profile['network.proxy.http'] = @geolocation.ip
              profile['network.proxy.http_port'] = @geolocation.port.to_i
              profile['network.proxy.ssl'] = @geolocation.ip
              profile['network.proxy.ssl_port'] = @geolocation.port.to_i
            when "socks"
              profile['network.proxy.socks'] = @geolocation.ip
              profile['network.proxy.socks_port'] = @geolocation.port.to_i
          end


        end


        Selenium::WebDriver::Firefox.path = @path_firefox
        client = Selenium::WebDriver::Remote::Http::Default.new
        client.read_timeout = 120 # seconds

        @driver = Selenium::WebDriver.for :firefox,
                                          :profile => profile,
                                          :http_client => client
        @driver.manage.timeouts.implicit_wait = 3
        @user_agent = @driver.execute_script("return navigator.userAgent")

      rescue Exception => e
        raise Error.new(FIREFOX_NOT_START, :error => e)

      else

      end
    end


  end


end
require_relative 'webscraper_gui'
require_relative 'webscraper_headless'