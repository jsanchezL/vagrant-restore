#!/usr/bin/env ruby

require 'rubygems'
require 'json'
require 'pp'
require 'rbconfig'

os = ""
#Comprueba sobre que esta corriendo ruby
if RUBY_PLATFORM =~ /win32/
  os = "win"
elsif RUBY_PLATFORM =~ /linux/
  os = "linux"
elsif RUBY_PLATFORM =~ /darwin/
  os = "mac"
else
  puts "Estamos corriendo sobre un OS desconocido, solo funcionamos por el momento en Windows, Mac y Linux"
  exit(true)
end

#Preguntamos por los generales antes de restaurar
puts "Bienvenido al Restore de Instancias de MerxBP : "
puts ""
puts "¿Es la primera vez que instalas la instancia?[s/n]"
primeraVez = gets.chomp
if primeraVez == ''
  primeraVez = 'N'
end
puts ""
puts "¿Cual es el nombre de la instancia? [Ejemplo: https://lowestest.sugarondemand.com -> Nombre de la instancia seria 'lowestest']"
nombreInstancia = gets.chomp
puts ""
puts "¿Ruta completa donde se encuentra vagrant en tu equipo?"
dirVagrant = gets.chomp
puts ""
puts "¿Necesitas ocupar repositorio Git?[s/n]"
respuestaGit = gets.chomp
if respuestaGit.capitalize == 'S'
  puts ""
  puts "Nombre del branch en GitHub (solo si se llama diferente al proyecto) [Ejemplo: Nombre de la instancia 'lowestest', nombre del branch en git 'lowes'] : "
  nameBranch = gets.chomp
  puts ""
  if nameBranch == ''
    nameBranch = nombreInstancia
  end
  puts "Usuario : "
  userGit = gets.chomp
  puts ""
  puts "Despues de completar la instalacion, ¿requieres correr las pruebas?[s/n]"
  correrPruebas = gets.chomp
  if correrPruebas == ''
    correrPruebas = 'S'
  end
end

#Carga el diccionario de datos y los parametros para ejecutar el script
file = File.read('dictionary-instancias-merx.json')
data_hash = JSON.parse(file)
instancias = data_hash["instancias-merx"]
params = instancias["#{nombreInstancia}"]

#Existe la instancia en el diccionario?
if !params.nil?
  #Es una instancia en ondemand u onsite
  if params["esOndemand"] == 'false'
    esOndemand = 'N'
    urlOnSite = params["urlOnSite"]
  else
    esOndemand = 'S'
    urlOnSite = 'N'
  end
  db_host_name = params['db_host_name']
  db_user_name = params['db_user_name']
  db_password = params['db_password']
  db_name = params['db_name']
  host_elastic = params['host_elastic']
else
  puts "No existe instancia con ese nombre, intenta de nuevo"
  exit(true)
end

if respuestaGit == 'S'
  paramsRestore = "#{primeraVez} #{nombreInstancia} #{dirVagrant} #{nameBranch} #{userGit} #{correrPruebas}"
else
  paramsRestore = "#{primeraVez} #{nombreInstancia} #{dirVagrant} N N N"
end

paramsInstancia = "#{esOndemand} #{urlOnSite} #{db_host_name} #{db_user_name} #{db_password} #{db_name} #{host_elastic}"
paramsScript = "#{paramsRestore} #{paramsInstancia}"

#Ejecuta un comando nativo del OS
if os == "linux"
  exec "./restoreVersionLinux.sh #{paramsScript}"
elsif os == "mac"
  exec "./restoreVersionMac.sh #{paramsScript}"
else
  puts "Estamos desarrollando una solucion para Windows"
end
