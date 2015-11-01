#charge un fichier parametre.yml et expose des methodes par paramètre du fichier
require 'pathname'
require 'yaml'
class Parameter

  #----------------------------------------------------------------------------------------------------------------
  # constant
  #----------------------------------------------------------------------------------------------------------------

  PARAMETER = File.expand_path(File.join("..", "..", "parameter"), __FILE__)
  ENVIRONMENT= File.join(PARAMETER, 'environment.yml')

  #----------------------------------------------------------------------------------------------------------------
  # attribut
  #----------------------------------------------------------------------------------------------------------------
  attr :parameters
  attr_reader :environment
  #----------------------------------------------------------------------------------------------------------------
  # class methods
  #----------------------------------------------------------------------------------------------------------------

  #----------------------------------------------------------------------------------------------------------------
  # initialize
  #----------------------------------------------------------------------------------------------------------------
  # prend en charge le remplacement du suffixe du fichier .rb -> .yml
  # charge un fichier de paramètre et sélectionne les paramètres en fonction de l'environement déclaré dans le fichier
  # environment.yml
  # le fichier de paramètre doit être localisé dans \statupbot\parameter
  #----------------------------------------------------------------------------------------------------------------
  # input :
  # le nom du fichier du composant qui veut charge un fichier de paramètre  : toto.rb
  #----------------------------------------------------------------------------------------------------------------
  def initialize(file_name)
    param_file_name = File.join(PARAMETER, "#{File.basename(file_name, '.rb')}.yml")

    raise "environment file not found" unless File.exist?(ENVIRONMENT)
    raise "parameter file not found" unless File.exist?(param_file_name)
    begin
      @environment = YAML::load(File.open(ENVIRONMENT), "r:UTF-8")['staging']
    rescue Exception => e
      raise "failed to load environment file #{e.message}"
    end
    begin
      @parameters = YAML::load(File.open(param_file_name), "r:UTF-8")[@environment]
    rescue Exception => e
      raise "failed to load parameter file #{e.message}"
    end
  end

  #----------------------------------------------------------------------------------------------------------------
  # instance methods
  #----------------------------------------------------------------------------------------------------------------

  #----------------------------------------------------------------------------------------------------------------
  # method_missing
  #----------------------------------------------------------------------------------------------------------------
  # retourne la valeur d'un paramètre
  # si le paramètre est absent du fichier alors retourne nil
  #----------------------------------------------------------------------------------------------------------------
  # input :
  # l'adresse d'un fichier de paramètre
  #----------------------------------------------------------------------------------------------------------------
  def method_missing (name, *args, &block)
    @parameters[name]
  end
end