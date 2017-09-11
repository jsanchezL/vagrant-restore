#!/usr/bin/env ruby

require 'rubygems'
require 'json'
require 'pp'
require 'rbconfig'
require 'fileutils'

class RestoreInstanciaVagrant
  @@os = nil
  @@diccionario = "dictionary-instancias-merx.json"
  @@gitMERX = "git@github.com:MerxBusinessPerformance/custom_sugarcrm.git"
  @@primeraVez = nil
  @@data_hash = nil
  @@nombreInstancia = nil
  @@paramsInstancia = nil
  @@dir_instancia = nil

  def initialize(primeraVez, nombreInstancia, respuestaGit, correrPruebas)
    os
    @@primeraVez = primeraVez
    leerDiccionario(nombreInstancia)
    procesar(respuestaGit,correrPruebas)
  end

  #Carga el diccionario de datos y los parametros para ejecutar el script
  def leerDiccionario(nombreInstancia)
    file = File.read(@@diccionario)
    @@data_hash = JSON.parse(file)
    instancias = @@data_hash["instancias-merx"]
    @@paramsInstancia = instancias["#{nombreInstancia}"]
    if @@paramsInstancia.nil?
      ingresarNombreDeLaInstanciaNuevamente
    else
      @@nombreInstancia = nombreInstancia
    end
  end

  def ingresarNombreDeLaInstanciaNuevamente
    puts "====> ¡No existe instancia con ese nombre! - Revisa tus datos e ingresa de nuevo el nombre de la instancia a restaurar:"
    nombreInstancia = gets.chomp
    leerDiccionario(nombreInstancia)
  end

  def procesar(respuestaGit, correrPruebas)
    if @@primeraVez != 'S'
      puts "Path de instalación con vagrant instalado y configurado"
      eliminarInstanciaObsoleta
      rutaBackup = extraerInstanciaNueva
      limpiarInstancia(rutaBackup)
      copiarArchivosAVagrant(rutaBackup)
      modificarConfig
      restaurarBDs
      ejecutarScripts
      cambiarPermisos
      if respuestaGit == 'S'
        obtenerCambiosDeGit
        if correrPruebas == 'S'
          instalarComposerYnpm
          repararInstancia
          ejecutarPruebas
        else
          recordatorioDeInstalacionComposerYnpm
          repararInstancia
        end
      end
    else
      puts "Path de instalación completamente nueva"
      #instalarVagrantEnEquipo()
      #editarVagrantFile()
      #recargarVagrant()
      #Pasos para la instancia -> Que incluya todos los Sistemas Operativos
    end
  end

  def eliminarInstanciaObsoleta
    @@dir_instancia = obtenerRutaInstancia
    puts " "
    puts "==> Eliminando instancia obsoleta..."
    if existe_directorio?(@@dir_instancia)
      limpiarDirectorio(@@dir_instancia)
    end
  end

  def extraerInstanciaNueva(nuevoIntento=false)
    rutaBackup = obtenerRutaBackup

    if !nuevoIntento
      puts " "
      puts "==> Extrayendo el restore..."
    else
      puts " "
      puts "==> Intentando nuevamente la extracción del restore..."
    end

    if existe_directorio?(rutaBackup)
      Dir.chdir(rutaBackup)
      # puts Dir.pwd
      if !esElUltimoBackup(rutaBackup)
        puts "====> ¡Se detecto que tienes más de un backup en ese directorio! - Por favor selecciona el más reciente:"
        nombreBackup = selecionarBackup(rutaBackup)
      else
        nombreBackup = "*.tar.gz"
      end

      limpiarDirectorio(rutaBackup+"/"+@@nombreInstancia+"*")

      if @@os == "linux" || @@os == "mac"
        puts "Extrayendo para mac y linux"
        result = system("tar -zxf #{nombreBackup}")
      elsif @@os == "win"
        puts "Extrayendo para windows"
        result = true #como se hace en winbugs?
      end

      if !result
        puts "====> ¡Error al momento de extraer el restore!"
        exit(!result)
      end
      return rutaBackup
    else
      ingresarRutaDelBackupManualmente
    end
  end

  def limpiarInstancia(ruta)
    puts " "
    puts "==> Limpiando la instancia..."
    restore = ruta+"/"+@@nombreInstancia+"*"
    restore = Dir.glob(restore).select{ |file| !File.file?(file) }[0]
    FileUtils.cd(restore)

    if existe_directorio?(Dir.glob("#{restore}/sugar*").select{ |file| !File.file?(file) }[0])
      limpiarDirectorio("#{restore}/sugar*/cache")      
      limpiarDirectorio("#{restore}/sugar*/upload")
      logs = Dir.glob("#{restore}/sugar*/*.log")
      logs.each_index do |l|
        File.delete(logs[l])
      end
      @@paramsInstancia['esOndemand'] = true
    elsif existe_directorio(Dir.glob("#{restore}/#{@@nombreInstancia}*").select{ |file| !File.file?(file) }) #instancias que no provengan de sugarondemand.com
      limpiarDirectorio("#{restore}/#{@@nombreInstancia}*/cache")
      limpiarDirectorio("#{restore}/#{@@nombreInstancia}*/upload")
      logs = Dir.glob("#{restore}/#{@@nombreInstancia}*/*.log")
      logs.each_index do |l|
        File.delete(logs[l])
      end
      @@paramsInstancia['esOndemand'] = false
    end
  end

  def copiarArchivosAVagrant(ruta)
    puts " "
    puts "==> Moviendo los archivos al directorio de Vagrant..."
    restore = ruta+"/"+@@nombreInstancia+"*"
    restore = Dir.glob(restore).select{ |file| !File.file?(file) }[0]
    FileUtils.cd(restore)
    if @@paramsInstancia['esOndemand']
      rutaRestore = Dir.glob("#{restore}/sugar*").select{ |file| !File.file?(file) }[0]
      FileUtils.cp_r rutaRestore, @@dir_instancia
      archivosSql = Dir.glob("#{restore}/*.sql").select{ |file| File.file?(file) }
      archivosSql.each_index do |i|
        FileUtils.cp archivosSql[i], @@dir_instancia
      end
    else
      rutaRestore = Dir.glob("#{restore}/#{@@nombreInstancia}*").select{ |file| !File.file?(file) }[0]
      FileUtils.cp_r rutaRestore, @@dir_instancia
      archivosSql = Dir.glob("#{restore}/*.sql").select{ |file| File.file?(file) }
      archivosSql.each_index do |i|
        FileUtils.cp archivosSql[i], @@dir_instancia
      end
    end
    Dir.chdir(ruta)
    limpiarDirectorio(restore)
  end

  def modificarConfig
    activarVagrant
    puts " "
    puts "==> Modificando archivo config.php y .htaccess..."

    system("vagrant ssh -c 'sed -i \"s/#{@@paramsInstancia['db_host_name']}/localhost/g\" /vagrant/#{@@nombreInstancia}.merxbp.loc/config.php'")
    system("vagrant ssh -c 'sed -i \"s/#{@@paramsInstancia['db_user_name']}/localhost/g\" /vagrant/#{@@nombreInstancia}.merxbp.loc/config.php'")
    system("vagrant ssh -c 'sed -i \"s/#{@@paramsInstancia['db_password']}/localhost/g\" /vagrant/#{@@nombreInstancia}.merxbp.loc/config.php'")
    system("vagrant ssh -c 'sed -i \"s/#{@@paramsInstancia['db_name']}/#{@@nombreInstancia}/g\" /vagrant/#{@@nombreInstancia}.merxbp.loc/config.php'")
    if @@paramsInstancia['esOndemand']
      system("vagrant ssh -c 'sed -i \"s/#{@@nombreInstancia}.sugarondemand.com/#{@@nombreInstancia}.merxbp.loc/g\" /vagrant/#{@@nombreInstancia}.merxbp.loc/config.php'")
      system("vagrant ssh -c 'sed -i \"s/#{@@paramsInstancia['db_name']}/#{@@nombreInstancia}/g\" /vagrant/#{@@nombreInstancia}*/*#{@@paramsInstancia['edicion']}.sql'")
  		system("vagrant ssh -c 'sed -i \"s/#{@@paramsInstancia['db_name']}/#{@@nombreInstancia}/g\" /vagrant/#{@@nombreInstancia}*/*triggers.sql'")
    else
      system("vagrant ssh -c 'sed -i \"s/#{@@paramsInstancia['urlOnSite']}/#{@@nombreInstancia}.merxbp.loc/g\" /vagrant/#{@@nombreInstancia}.merxbp.loc/config.php'")
      system("vagrant ssh -c 'sed -i \"s/#{@@paramsInstancia['db_name']}/#{@@nombreInstancia}/g\" /vagrant/#{@@nombreInstancia}*/*.sql'")
    end
    system("vagrant ssh -c 'sed -i \"s/#{@@paramsInstancia['host_elastic']}/localhost/g\" /vagrant/#{@@nombreInstancia}.merxbp.loc/config.php'")
    httacces = "vagrant ssh -c 'sed -i \"s/RewriteBase "+'\//RewriteBase \/sugar\/'+"#{@@nombreInstancia}.merxbp.loc"+'\//g"'+" /vagrant/#{@@nombreInstancia}.merxbp.loc/.htaccess'"
    system(httacces)
  end

  def activarVagrant
    Dir.chdir(@@data_hash["vagrant"]['dir_base'])
    system("vagrant reload")
  end

  def restaurarBDs
    puts " "
    puts "==> Restaurando bases de datos..."
    system("vagrant ssh -c \"mysql -u root -proot -e 'drop database IF EXISTS #{@@nombreInstancia}; create database #{@@nombreInstancia}; show databases;'\"")
    if @@paramsInstancia['esOndemand']
      system("vagrant ssh -c \"mysql -u root -proot #{@@nombreInstancia} < /vagrant/#{@@nombreInstancia}.merxbp.loc/*#{@@paramsInstancia['edicion']}.sql\"")
      system("vagrant ssh -c \"mysql -u root -proot #{@@nombreInstancia} < /vagrant/#{@@nombreInstancia}.merxbp.loc/*#{@@paramsInstancia['edicion']}_triggers.sql\"")
    else
      system("vagrant ssh -c \"mysql -u root -proot #{@@nombreInstancia} < /vagrant/#{@@nombreInstancia}.merxbp.loc/*.sql\"")
    end
    puts ""
    system("vagrant ssh -c \"mysql -u root -proot -e 'drop database IF EXISTS #{@@nombreInstancia}_origin; create database #{@@nombreInstancia}_origin; show databases;'\"")
    if @@paramsInstancia['esOndemand']
      system("vagrant ssh -c \"mysql -u root -proot #{@@nombreInstancia}_origin < /vagrant/#{@@nombreInstancia}.merxbp.loc/*#{@@paramsInstancia['edicion']}.sql\"")
      system("vagrant ssh -c \"mysql -u root -proot #{@@nombreInstancia}_origin < /vagrant/#{@@nombreInstancia}.merxbp.loc/*#{@@paramsInstancia['edicion']}_triggers.sql\"")
    else
      system("vagrant ssh -c \"mysql -u root -proot #{@@nombreInstancia}_origin < /vagrant/#{@@nombreInstancia}.merxbp.loc/*.sql\"")
    end
  end

  def ejecutarScripts
    if !@@paramsInstancia['db_scripts'].empty?
      puts " "
      puts "==> Ejecuntando scripts de base de datos..."
      scripts = @@paramsInstancia['db_scripts']
      scripts.each_index do |i|
        system("vagrant ssh -c 'mysql -u root -proot #{@@nombreInstancia} -e \"#{scripts[i]}\"'")
      end
    end
  end

  def cambiarPermisos
    puts " "
    puts "==> Cambiando permisos a los archivos de la instancia..."
    system("vagrant ssh -c \"chmod 755 -R /vagrant/#{@@nombreInstancia}.merxbp.loc\"")
  end

  def instalarComposerYnpm
    puts " "
    puts "==> Instalando composer y npm..."
    system("vagrant ssh -c \"cd /vagrant/#{@@nombreInstancia}.merxbp.loc; composer install\"")
    system("vagrant ssh -c \"cd /vagrant/#{@@nombreInstancia}.merxbp.loc; npm install\"")
  end

  def recordatorioDeInstalacionComposerYnpm
    puts " "
    puts "====> ¡Recuerda antes de correr tus pruebas, instala composer y npm con las siguientes lineas! : "
    puts "vagrant ssh -c 'cd /vagrant/${proyecto}.merxbp.loc; composer install'"
    puts "vagrant ssh -c 'cd /vagrant/${proyecto}.merxbp.loc; npm install'"
  end

  def obtenerCambiosDeGit
    Dir.chdir(@@dir_instancia)
    puts " "
    puts "==> Obteniendo cambios de Git..."
    system("touch .gitignore")
    system("git init")
    system("git add .gitignore")
    system("git commit -m \"Primer commit\"")
    system("echo \"*\" > .gitignore")
    system("git add .gitignore")
    system("git commit -m \"Omitiendo archivos\"")
    system("git remote add merx \"#{@@gitMERX}\"")
    system("git remote add origin \"git@github.com:#{@@data_hash["github"]["user"]}/custom_sugarcrm.git\"")
    system("git fetch merx")
    system("git fetch origin")
    system("git checkout -b #{@@paramsInstancia['branch']} merx/#{@@paramsInstancia['branch']}")
  end

  def repararInstancia
    Dir.chdir(@@data_hash["vagrant"]['dir_base'])
    puts "==> Reparando la instancia..."
    system("vagrant ssh -c \"cd /vagrant/#{@@nombreInstancia}.merxbp.loc; php repair.php\"")
  end

  def ejecutarPruebas
    puts " "
    puts "==> Ejecutando las pruebas PHP..."
    system("vagrant ssh -c \"cd /vagrant/#{@@nombreInstancia}.merxbp.loc/tests; ../vendor/phpunit/phpunit/phpunit\"")
    puts " "
    puts "==> Ejecutando las pruebas JS..."
    puts "Sólo falta esta parte."
  end

  def limpiarDirectorio(ruta)
    directorios = Dir.glob(ruta).select { |file| !File.file?(file) }
    if !directorios.empty?
      directorios.each_index do |d|
        FileUtils.remove_dir(directorios[d],true)
      end
    end
  end

  #Detecta si hay más de un backup en el directorio
  def esElUltimoBackup(ruta)
    if Dir.glob(File.join(ruta, '**', '*tar.gz')).select { |file| File.file?(file) }.count == 1
      return true
    else
      return false
    end
  end

  def selecionarBackup(ruta)
    backups = Dir.glob(File.join(ruta, '**', '*tar.gz')).select { |file| File.file?(file) }
    backups.each_index do |i|
      index = i+1
      puts "#{index}) #{File.split(backups[i]).last}"
    end
    puts "Selección?"
    seleccion = gets.chomp.to_i
    seleccion = seleccion-1
    return File.split(backups[seleccion]).last
  end

  def ingresarRutaDelBackupManualmente
    puts "====> ¡No se encontró ruta del Backup! - Determina la ruta adecuada e ingresa manualmente la ruta para continuar:"
    @@paramsInstancia['dir_backup'] = gets.chomp
    extraerInstanciaNueva(true)
  end

  def obtenerRutaBackup
    if !@@paramsInstancia['dir_backup'].empty?
      return @@paramsInstancia['dir_backup']
    else
      return Dir.pwd + "/proyectos/" + @@nombreInstancia + "/backups/lastest"
    end
  end

  def obtenerRutaInstancia
    @@data_hash["vagrant"]['dir_base'] + "/" + @@nombreInstancia + ".merxbp.loc"
  end

  def existe_directorio?(directory)
    File.directory?(directory)
  end

  #Investiga que plataforma estamos utilizando
  def os
    if RUBY_PLATFORM =~ /win32/
      @@os = "win"
    elsif RUBY_PLATFORM =~ /linux/
      @@os = "linux"
    elsif RUBY_PLATFORM =~ /darwin/
      @@os = "mac"
    else
      puts "Estamos corriendo sobre un OS desconocido, solo funcionamos por el momento en Windows, Mac y Linux"
      exit(true)
    end
  end

end

system("clear")

#Preguntamos por los generales antes de restaurar
puts "Bienvenido al Restore de Instancias de MerxBP : "
puts ""
puts "¿Es la primera vez que instalas una instancia en este equipo?[s/n]"
primeraVez = gets.chomp.capitalize
if primeraVez == '' || primeraVez != 'S'
  primeraVez = 'N'
end
puts ""
puts "¿Cuál es el nombre de la instancia? [Ejemplo: https://lowestest.sugarondemand.com -> Nombre de la instancia sería 'lowestest']"
nombreInstancia = gets.chomp
while nombreInstancia.empty?
  puts "Nombre de la instancia, por favor?"
  nombreInstancia = gets.chomp
end
puts ""
puts "¿Necesitas ocupar repositorio Git?[s/n]"
respuestaGit = gets.chomp.capitalize
if respuestaGit == '' || respuestaGit != 'S'
  respuestaGit = 'N'
  correrPruebas = 'N'
elsif respuestaGit == 'S'
  puts ""
  puts "Después de completar la instalación, ¿requieres correr las pruebas?[s/n]"
  correrPruebas = gets.chomp.capitalize
  if correrPruebas == '' || correrPruebas != 'S'
    correrPruebas = 'N'
  end
end

restore = RestoreInstanciaVagrant.new(primeraVez, nombreInstancia, respuestaGit, correrPruebas)
