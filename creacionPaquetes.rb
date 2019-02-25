#!/usr/bin/env ruby

require 'rubygems'
require 'json'
require 'rbconfig'
require 'fileutils'
require 'colorize'

class ConstruyeT
  @@dir = "/home/jsanchez/Documentos/merx/jsanchezL"
  @@dir_packages = "/home/jsanchez/Documentos/merx/jsanchezL/sugarcrm_packages"
  @@gitMERX = "git@github.com:MerxBusinessPerformance/sugarcrm_packages.git"
  @@dir_packages_build = "/home/jsanchez/Documentos/merx/jsanchezL/builds"
  @@diccionario = "Merxfile.json"
  @@instancia = nil
  @@dir_scriptrb = nil

  def initialize(instancia,git)
    @@instancia = instancia
    if git.to_s == 'S'
      gitLocalDirFromRemote
    end
    @@dir_scriptrb = Dir.pwd
    file = File.read(File.join(@@dir_packages, "#{@@diccionario}"))
    data_hash = JSON.parse(file)
    dependencies = data_hash["dependencies"]

    puts " "
    puts "==> Creación de paquetes...".green
    dependencies.each do |k,v|
      dir_package = File.join(@@dir_packages, k)
      Dir.chdir(dir_package)
      package = File.join(dir_package, "#{k}.zip")
      puts ""
      puts "====>Creando paquete #{k}".green
      system("zip -r #{package} . -x .DS_Store *.md *.sonarlint* *.directory*")
      FileUtils.cp File.join(dir_package, "#{k}.zip"), File.join(@@dir_packages_build,@@instancia)
    end
    puts ""
  end


  def gitLocalDirFromRemote()
    puts " "
    puts "==> Obteniendo cambios de Git...".green
    if existe_directorio?(@@dir_packages)
      puts " "
      puts "====> Actualizando repositorio #{@@instancia} de MerxBP...".green
      Dir.chdir(@@dir_packages)
      system("git fetch origin #{@@instancia}")
      res = `git branch`
      exp = /#{@@instancia}/
      ar = res.to_s.split("\n")      
      flag = false
      
      ar.each do |i|
        if exp.match(i.to_s.strip)
          flag = true          
        end
      end
      
      if !flag  
        system("git checkout -b #{@@instancia} origin/#{@@instancia}")
      else
        system("git checkout #{@@instancia}")
      end
      system("git merge origin/#{@@instancia}")
      
    else
      puts " "
      puts "====> Creando repositorio #{localOrPaquetes} de MerxBP...".green
      Dir.chdir(@@dir)
      system("git clone #{@@gitMERX}")
      Dir.chdir(@@dir_packages)
      res = `git branch`
      exp = /\*\s#{@@instancia}/
      if !exp.match(res)
        system("git checkout -b #{@@instancia} origin/#{@@instancia}")
      else
        system("git checkout #{@@instancia}")
      end
    end
  end

  def existe_directorio?(directory)
    File.directory?(directory)
  end

  def existe_archivo?(file)
    File.file?(file)
  end

end

system("clear")
system("cls")

#Preguntamos por los generales antes de restaurar
puts "====================================================".green
puts "|                                                  |".green
puts "|  Bienvenido al Constructor de paquetes para las  |".green
puts "|  instancias de MerxBP                            |".green
puts "|                                                  |".green
puts "====================================================".green
puts ""

if ARGV.length != 0
  instancia = ARGV[0].chomp 
  
  if ARGV.length > 1   
    arg0 = ARGV[1].upcase.chomp
    if arg0 != "N" && arg0 != "S"
      git = "N"
    else
      git = arg0;
    end
  else
    git = "N"
  end
else
  puts "Se esperaba el nombre de la instancia o branch para iniciar el proceso".red
  puts ""
  exit(true)
end

constructor = ConstruyeT.new(instancia,git)
