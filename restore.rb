#!/usr/bin/env ruby

require 'rubygems'
require 'json'
require 'rbconfig'
require 'fileutils'
require 'colorize'

class RestoreInstanciaVagrant
  @@os = nil
  @@diccionario = "dictionary-instancias-merx.json"
  @@gitMERX = nil
  @@primeraVez = nil
  @@data_hash = nil
  @@nombreInstancia = nil
  @@paramsInstancia = nil
  @@dir_instancia = nil
  @@dir_scriptrb = nil

  def initialize(primeraVez, nombreInstancia, tipoRestore, respuestaGit, correrPruebas)
    os
    @@dir_scriptrb = Dir.pwd
    @@primeraVez = primeraVez
    leerDiccionario(nombreInstancia)
    procesar(tipoRestore,respuestaGit,correrPruebas)
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
    puts "====> ¡No existe instancia con ese nombre! - Revisa tus datos e ingresa de nuevo el nombre de la instancia a restaurar:".red
    nombreInstancia = gets.chomp
    leerDiccionario(nombreInstancia)
  end

  def procesar(tipoRestore, respuestaGit, correrPruebas)
    tiempoDeInicio = Time.new.to_i
    puts ""
    puts "==> Iniciando...".green
    if @@primeraVez != 'S'
      if tipoRestore == 'T'
        eliminarInstanciaObsoleta
      elsif tipoRestore == 'G'
        eliminarRepoGit
      elsif tipoRestore == 'B' && respuestaGit == 'S'
        eliminarRepoGit
      end
    else
      instalarVagrantBoxEnEquipo
      editarVagrantFile
      activarVagrant
    end
    Dir.chdir(@@dir_scriptrb)
    if tipoRestore == 'T' #Todo
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
    elsif tipoRestore == 'G' #Sólo git
      obtenerCambiosDeGit
      if correrPruebas == 'S'
        instalarComposerYnpm
        repararInstancia
        ejecutarPruebas
      else
        recordatorioDeInstalacionComposerYnpm
        repararInstancia
      end
    elsif tipoRestore == 'B' #Base de datos
      activarVagrant
      restaurarBDs
      ejecutarScripts
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
    end
    tiempoDeFin = Time.new.to_i
    tiempoDeProceso = ( tiempoDeFin - tiempoDeInicio ) / 60

    puts "==> Terminando...".green
    puts " "
    puts "==> Finalizado en #{tiempoDeProceso} mins.".green
  end

  def instalarVagrantBoxEnEquipo
    Dir.chdir(@@data_hash["vagrant"]['dir_base'])
    puts " "
    puts "==> Instalando Vagrant Box...".green
    if @@paramsInstancia['version'].to_i < 7710
      system("vagrant init mmarum/sugar7-php54")
    else
      system("vagrant init mmarum/sugar7-php56")
    end
    system("vagrant up --provider virtualbox")
  end

  def editarVagrantFile
    puts " "
    puts "==> Editando el Vagrantfile...".green

    expresionsOrigin = [
      '# config.vm.network "forwarded_port", guest: 80, host: 8080',
      '# config.vm.network "private_network", ip: "192.168.33.10"',
      '# config.vm.synced_folder "../data", "/vagrant_data"'
    ]
    expresionsReplace = [
      'config.vm.network "forwarded_port", guest: 80, host: 8080',
      'config.vm.network "private_network", ip: "192.168.33.10"',
      'config.vm.synced_folder ".", "/vagrant", type: "nfs"'
    ]
    filename = "Vagrantfile"

    expresionsOrigin.each_index do |i|
      text = File.read(filename)
      expO = expresionsOrigin[i]
      expR = expresionsReplace[i]
      content = text.gsub(/#{expO}$/, "#{expR}")
      if @@os == "win" && i < 2
        # puts content
        File.open(filename, "w") { |file| file << content }
      elsif @@os != "win"
        # puts content
        File.open(filename, "w") { |file| file << content }
      end
    end
  end

  def eliminarInstanciaObsoleta
    @@dir_instancia = obtenerRutaInstancia
    puts " "
    puts "==> Eliminando instancia obsoleta...".green
    if existe_directorio?(@@dir_instancia)
      limpiarDirectorio(@@dir_instancia)
    end
  end

  def extraerInstanciaNueva(nuevoIntento=false)
    rutaBackup = obtenerRutaBackup

    if !nuevoIntento
      puts " "
      puts "==> Extrayendo el restore...".green
    else
      puts " "
      puts "==> Intentando nuevamente la extracción del restore...".yellow
    end

    if existe_directorio?(rutaBackup)
      Dir.chdir(rutaBackup)

      if !esElUltimoBackup(rutaBackup)
        puts "====> ¡Se detecto que tienes más de un backup en ese directorio! - Por favor selecciona el más reciente:".yellow
        nombreBackup = seleccionarBackup(rutaBackup)
      else
        nombreBackup = "*.tar.gz"
      end

      if @@os == "linux" || @@os == "mac"
        limpiarDirectorio(File.join(rutaBackup,@@nombreInstancia+'*'))
        result = system("tar -zxf #{nombreBackup}")
      elsif @@os == "win"
        nombreBackupTar = "*.tar"
        carpetaAnterior = File.join(rutaBackup,@@nombreInstancia+'*').gsub(%r{\\}) {'/'}
        archivoTar = File.join(rutaBackup,@@nombreInstancia+nombreBackupTar).gsub(%r{/}) {'\\'}
        limpiarDirectorio(carpetaAnterior)
        system("del /Q #{archivoTar}")
        result = system("7z e -aoa #{nombreBackup}")
        result = system("7z x -aoa #{nombreBackupTar}")
      end

      if !result
        puts "====> ¡Error al momento de extraer el restore!".red
        exit(!result)
      end

      return rutaBackup
    else
      ingresarRutaDelBackupManualmente
    end
  end

  def limpiarInstancia(ruta)
    puts " "
    puts "==> Limpiando la instancia...".green
    restore = File.join(ruta,@@nombreInstancia+'*')
    if @@os == "win"
      restore = restore.gsub(%r{\\}) {'/'}
    end
    restore = Dir.glob(restore).select{ |file| !File.file?(file) }[0]
    FileUtils.cd(restore)

    sugardir = Dir.glob(File.join(restore,'sugar*')).select{ |file| !File.file?(file) }[0]
    if existe_directorio?(sugardir)
      cache = File.join(sugardir, "cache")
      upload = File.join(sugardir, "upload")
      limpiarDirectorio(cache)
      limpiarDirectorio(upload)

      if @@os != "win"
        Dir.mkdir(cache)
        Dir.mkdir(upload)
      else
        cache = cache.gsub(%r{/}) {'\\'}
        upload = upload.gsub(%r{/}) {'\\'}
        system("mkdir #{cache}")
        system("mkdir #{upload}")
        system("attrib #{restore} /S /D -S -A -R -I")
      end

      logs = Dir.glob(File.join(sugardir, "*.log"))
      logs.each_index do |l|
        File.delete(logs[l])
      end
      @@paramsInstancia['esOndemand'] = true
    elsif existe_directorio(Dir.glob("#{restore}/#{@@nombreInstancia}*").select{ |file| !File.file?(file) }[0]) #instancias que no provengan de sugarondemand.com
      instanciaDir = Dir.glob("#{restore}/#{@@nombreInstancia}*").select{ |file| !File.file?(file) }[0]
      cache = File.join(instanciaDir, "cache")
      upload = File.join(instanciaDir, "upload")
      limpiarDirectorio(cache)
      limpiarDirectorio(upload)

      if @@os != "win"
        Dir.mkdir(cache)
        Dir.mkdir(upload)
      else
        cache = cache.gsub(%r{/}) {'\\'}
        upload = upload.gsub(%r{/}) {'\\'}
        system("mkdir #{cache}")
        system("mkdir #{upload}")
        system("attrib #{restore} /S /D -S -A -R -I")
      end
      logs = Dir.glob(File.join(instanciaDir, "*.log"))
      logs.each_index do |l|
        File.delete(logs[l])
      end
      @@paramsInstancia['esOndemand'] = false
    end
  end

  def copiarArchivosAVagrant(ruta)
    @@dir_instancia = obtenerRutaInstancia
    puts " "
    puts "==> Moviendo los archivos al directorio de Vagrant...".green
    restore = File.join(ruta,@@nombreInstancia+'*')
    if @@os == "win"
      restore = restore.gsub(%r{\\}) {'/'}
    end
    restore = Dir.glob(restore).select{ |file| !File.file?(file) }[0]
    FileUtils.cd(restore)

    if @@paramsInstancia['esOndemand']
      rutaRestore = Dir.glob(File.join(restore,"sugar*")).select{ |file| !File.file?(file) }[0]
      archivoSql = File.join(restore,"*.sql")

      if @@os == "win"
        rutaRestore = rutaRestore.gsub(%r{/}) {'\\'}
        dir_instancia = @@dir_instancia.gsub(%r{/}) {'\\'}
        system("attrib #{@@data_hash['vagrant']['dir_base']} /S /D -S -A -R -I")
        system("move /Y #{rutaRestore} #{dir_instancia}")
      else
        FileUtils.cp_r rutaRestore, @@dir_instancia
      end
      archivosSql = Dir.glob(archivoSql).select{ |file| File.file?(file) }
      archivosSql.each_index do |i|
        if @@os == "win"
          FileUtils.cp archivosSql[i].gsub(%r{/}) {'\\'}, dir_instancia
        else
          FileUtils.cp archivosSql[i], @@dir_instancia
        end
      end
    else
      rutaw = File.join(restore,@@nombreInstancia+'*')
      rutaRestore = Dir.glob(rutaw).select{ |file| !File.file?(file) }[0]
      archivoSql = File.join(rutaw,"*.sql")

      if @@os == "win"
        rutaRestore = rutaRestore.gsub(%r{/}) {'\\'}
        dir_instancia = @@dir_instancia.gsub(%r{/}) {'\\'}
        system("move /Y #{rutaRestore} #{dir_instancia}")
      else
        FileUtils.cp_r rutaRestore, @@dir_instancia
      end

      archivosSql = Dir.glob(archivoSql).select{ |file| File.file?(file) }
      archivosSql.each_index do |i|
        if @@os == "win"
          FileUtils.cp archivosSql[i].gsub(%r{/}) {'\\'}, dir_instancia
        else
          FileUtils.cp archivosSql[i], @@dir_instancia
        end
      end
    end
    Dir.chdir(ruta)
    limpiarDirectorio(restore)
    if @@os == "win"
      nombreBackupTar = "*.tar"
      archivoTar = File.join(restore+nombreBackupTar).gsub(%r{/}) {'\\'}
      system("del /Q #{archivoTar}")
    end
  end

  def modificarConfig
    activarVagrant
    puts " "
    puts "==> Modificando archivo config.php y .htaccess...".green

    system("vagrant ssh -c 'sed -i \"s/#{@@paramsInstancia['db_host_name']}/localhost/g\" /vagrant/#{@@nombreInstancia}.merxbp.loc/config.php'")
    system("vagrant ssh -c 'sed -i \"s/#{@@paramsInstancia['db_user_name']}/root/g\" /vagrant/#{@@nombreInstancia}.merxbp.loc/config.php'")
    system("vagrant ssh -c 'sed -i \"s/#{@@paramsInstancia['db_password']}/root/g\" /vagrant/#{@@nombreInstancia}.merxbp.loc/config.php'")
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

    if @@os == 'win'
      httacces = "vagrant ssh -c \"sed -i 's/RewriteBase "+'\//RewriteBase \/sugar\/'+"#{@@nombreInstancia}.merxbp.loc"+'\//g\''+" /vagrant/#{@@nombreInstancia}.merxbp.loc/.htaccess\""
    else
      httacces = "vagrant ssh -c 'sed -i \"s/RewriteBase "+'\//RewriteBase \/sugar\/'+"#{@@nombreInstancia}.merxbp.loc"+'\//g"'+" /vagrant/#{@@nombreInstancia}.merxbp.loc/.htaccess'"
    end
    system(httacces)
  end

  def activarVagrant
    Dir.chdir(@@data_hash["vagrant"]['dir_base'])
    if @@os != 'win'
      res = `curl -I -s -L http://localhost:8080 | grep 'HTTP/1.1'`
      if !res.include? "200"
        puts " "
        puts "Iniciando vagrant...".green
        system("vagrant reload")
      end
    else
      puts "proceso en Windows"
    end
  end

  def restaurarBDs
    puts " "
    puts "==> Restaurando bases de datos...".green
    system("vagrant ssh -c \"mysql -u root -proot -e 'drop database IF EXISTS #{@@nombreInstancia}; create database #{@@nombreInstancia}; show databases;'\"")
    if @@paramsInstancia['esOndemand']
      system("vagrant ssh -c \"mysql -u root -proot #{@@nombreInstancia} < /vagrant/#{@@nombreInstancia}.merxbp.loc/*#{@@paramsInstancia['edicion']}.sql\"")
      system("vagrant ssh -c \"mysql -u root -proot #{@@nombreInstancia} < /vagrant/#{@@nombreInstancia}.merxbp.loc/*#{@@paramsInstancia['edicion']}_triggers.sql\"")
    else
      system("vagrant ssh -c \"mysql -u root -proot #{@@nombreInstancia} < /vagrant/#{@@nombreInstancia}.merxbp.loc/*.sql\"")
    end
    puts ""
    puts "===> Origin copia de respaldo de la bd".green
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
      puts "==> Ejecuntando scripts de base de datos...".green
      scripts = @@paramsInstancia['db_scripts']
      scripts.each_index do |i|
        if @@os == "win"
          commando = "vagrant ssh -c \"mysql -u root -proot #{@@nombreInstancia} -e '#{scripts[i]}'\""
        else
          commando = "vagrant ssh -c 'mysql -u root -proot #{@@nombreInstancia} -e \"#{scripts[i]}\"'"
        end
        system(commando)
      end
    end
  end

  def cambiarPermisos
    puts " "
    puts "==> Cambiando permisos a los archivos de la instancia...".green
    system("vagrant ssh -c \"chmod 755 -R /vagrant/#{@@nombreInstancia}.merxbp.loc\"")
  end

  def instalarComposerYnpm
    puts " "
    puts "==> Instalando composer y npm...".green
    system("vagrant ssh -c \"cd /vagrant/#{@@nombreInstancia}.merxbp.loc; composer install\"")
    system("vagrant ssh -c \"cd /vagrant/#{@@nombreInstancia}.merxbp.loc; npm install\"")
  end

  def recordatorioDeInstalacionComposerYnpm
    puts " "
    puts "====> ¡Recuerda antes de correr tus pruebas, instala composer y npm, desde el directorio vagrant con las siguientes lineas! : ".red
    puts "========> vagrant ssh -c 'cd /vagrant/#{@@nombreInstancia}.merxbp.loc; composer install'".red
    puts "========> vagrant ssh -c 'cd /vagrant/#{@@nombreInstancia}.merxbp.loc; npm install'".red

  end

  # Checar el comportamiento de esta modificacion

  def gitLocalDirFromRemote
    @@gitMERX = @@data_hash['github']['local']['remote']
    dirRepoMerx = @@gitMERX.split('/').last
    dirRepoMerx = dirRepoMerx.split('.').first
    gitLocal = File.join(@@data_hash['github']['local']['dir'],dirRepoMerx)

    if existe_directorio?(gitLocal)
      puts " "
      puts "==> Actualizando repositorio local de MerxBP...".green
      Dir.chdir(gitLocal)
      system("git fetch origin #{@@paramsInstancia['branch']}")
      system("git merge origin/#{@@paramsInstancia['branch']}")
    else
      puts " "
      puts "==> Creando repositorio local de MerxBP...".green
      Dir.chdir(@@data_hash['github']['local']['dir'])
      system("git clone #{@@gitMERX}")
    end
    return gitLocal
  end

  def obtenerCambiosDeGit
    puts " "
    puts "==> Obteniendo cambios de Git...".green
    gitLocal = gitLocalDirFromRemote

    Dir.chdir(@@dir_instancia)

    if @@os != "win"
      system("touch .gitignore")
    else
      system("copy NUL .gitignore")
      gitLocal = gitLocal.gsub(%r{/}) {'\\'}
    end

    system("git init")
    system("git add .gitignore")
    system("git commit -m \"Primer commit\"")
    if @@os != "win"
      system("echo \"*\" > .gitignore")
    else
      system("echo * > .gitignore")
    end

    system("git add .gitignore")
    system("git commit -m \"Omitiendo archivos\"")
    system("git remote add local #{gitLocal}")
    system("git remote add merx \"#{@@gitMERX}\"")
    system("git remote add origin \"git@github.com:#{@@data_hash["github"]["user"]}/custom_sugarcrm.git\"")
    # system("git fetch merx")
    system("git fetch local #{@@paramsInstancia['branch']}")
    # system("git fetch origin")
    # system("git checkout -b #{@@paramsInstancia['branch']} merx/#{@@paramsInstancia['branch']}")
    system("git checkout -b #{@@paramsInstancia['branch']} local/#{@@paramsInstancia['branch']}")
    # system("git clean -i")
    # system("git pull local #{@@paramsInstancia['branch']} --allow-unrelated-histories")
  end

  def repararInstancia
    Dir.chdir(@@data_hash["vagrant"]['dir_base'])
    puts " "
    puts "==> Reparando la instancia...".green
    system("vagrant ssh -c \"cd /vagrant/#{@@nombreInstancia}.merxbp.loc; php repair.php\"")
  end

  def ejecutarPruebas
    puts " "
    puts "==> Ejecutando las pruebas PHP...".green
    system("vagrant ssh -c \"cd /vagrant/#{@@nombreInstancia}.merxbp.loc/tests; ../vendor/phpunit/phpunit/phpunit\"")
    puts " "
    puts "==> Ejecutando las pruebas JS...".green
    if @@paramsInstancia['version'].to_i < 7800
      system("vagrant ssh -c \"cd /vagrant/#{@@nombreInstancia}.merxbp.loc/tests; grunt karma:ci\"")
    else
      system("vagrant ssh -c \"cd /vagrant/#{@@nombreInstancia}.merxbp.loc/node_modules/gulp/bin/gulp.js karma --ci\"")
    end
  end

  def limpiarDirectorio(ruta)
    directorios = Dir.glob(ruta).select { |file| !File.file?(file) }
    if !directorios.empty?
      directorios.each_index do |d|
        if @@os == "win"
          dir = directorios[d].gsub(%r{/}) {'\\'}
          system("rmdir /S /Q #{dir}")
        else
          FileUtils.remove_dir(directorios[d],true)
        end
      end
    end
  end

  #Detecta si hay más de un backup en el directorio
  def esElUltimoBackup(ruta)
    if Dir.glob('*tar.gz').select { |file| File.file?(file) }.count == 1
      return true
    else
      return false
    end
  end

  #Preguntamos por un directorio personalizado del backup
  def seleccionarBackup(ruta)
    backups = Dir.glob('*.tar.gz').select { |file| File.file?(file) }

    backups.each_index do |i|
      index = i+1
      puts "#{index}) #{File.split(backups[i]).last}"
    end
    puts "Selección?".yellow
    seleccion = gets.chomp.to_i
    seleccion = seleccion-1
    if seleccion == (backups.length-1)
      return File.split(backups[seleccion]).last
    else
      while seleccion < 0 || seleccion > (backups.length-1)
        puts "Selección?".yellow
        seleccion = gets.chomp.to_i
        seleccion = seleccion-1
      end
      return File.split(backups[seleccion]).last
    end
  end

  def ingresarRutaDelBackupManualmente
    puts "====> ¡No se encontró ruta del Backup! - Determina la ruta adecuada e ingresa manualmente la ruta para continuar:".red
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
    if (/cygwin|mswin|mingw|bccwin|wince|emx/ =~ RUBY_PLATFORM) != nil
      @@os = "win"
    elsif RUBY_PLATFORM =~ /linux/
      @@os = "linux"
    elsif (/darwin/ =~ RUBY_PLATFORM) != nil
      @@os = "mac"
    else
      puts "====> Estamos corriendo sobre un OS desconocido, solo funcionamos por el momento en Windows, Mac y Linux".red
      exit(true)
    end
  end

  def eliminarRepoGit
    @@dir_instancia = obtenerRutaInstancia
    puts " "
    puts "==> Eliminando repositorio Git...".green
    dirRepo = File.join(@@dir_instancia,'.git')
    if existe_directorio?(dirRepo)
      limpiarDirectorio(dirRepo)
      if @@os == "win"
        gitignore = File.join(@@dir_instancia,".gitignore").gsub(%r{/}) {'\\'}
        system("del /Q #{gitignore}")
      else
        File.delete(File.join(@@dir_instancia,".gitignore"))
      end
    end
  end
end



system("clear")
system("cls")

#Preguntamos por los generales antes de restaurar
puts "====================================================".green
puts "|                                                  |".green
puts "|  Bienvenido al Restore de Instancias de MerxBP   |".green
puts "|                                                  |".green
puts "====================================================".green
puts ""
puts ""
error = false
if ARGV.length != 0
  if ARGV.length == 1
    puts "Se esperaba al menos 2 parametros para iniciar el proceso".red
    puts ""
    error = true
  elsif ARGV.length == 2
    arg0 = ARGV[0].upcase.chomp
    if arg0 != "N" && arg0 != "S"
      puts "Se esperaba que el primer parametro fuera N o S".red
      puts ""
      error = true
    end
    primeraVez = arg0
    nombreInstancia = ARGV[1].chomp
    tipoRestore = 'T'
    respuestaGit = 'S'
    correrPruebas = 'S'
  elsif ARGV.length == 3
    arg0 = ARGV[0].upcase.chomp
    if arg0 != "S" && arg0 != "N"
      puts ""
      puts ""
      puts "Se esperaba que el primer parametro fuera N o S".red
      puts ""
      exit(true)
    end
    arg2 = ARGV[2].upcase.chomp
    if arg2 == "T" || arg2 == "G" ||  arg2 == "B"
      if arg2 == "T"
        respuestaGit = 'S'
        correrPruebas = 'S'
      elsif arg2 == "B"
        respuestaGit = 'N'
        correrPruebas = 'N'
      else
        respuestaGit = 'S'
        correrPruebas = 'N'
      end
      primeraVez = arg0
      nombreInstancia = ARGV[1].chomp
      tipoRestore = arg2
    else
      puts "Se esperaba que el tercer parametro fuera el tipo del restore: T[Todo], G[Git], B[Base de Datos]".red
      puts ""
      error = true
    end
  elsif ARGV.length == 4
    arg0 = ARGV[0].upcase.chomp
    if arg0 != "S" && arg0 != "N"
      puts "Se esperaba que el primer parametro fuera N o S".red
      puts ""
      error = true
    end
    arg2 = ARGV[2].upcase.chomp
    if !(arg2 == "T" || arg2 == "G" || arg2 == "B")
      puts "Se esperaba que el tercer parametro fuera el tipo del restore: T[Todo], G[Git], B[Base de Datos]".red
      puts ""
      error = true
    end
    arg3 = ARGV[3].upcase.chomp
    if arg3 != "S" && arg3 != "N"
      puts "Se esperaba que el cuarto parametro fuera N o S".red
      puts ""
      error = true
    end
    if arg3 == "S"
      respuestaGit = arg3
      correrPruebas = 'N'
    else
      respuestaGit = 'N'
      correrPruebas = 'N'
    end
    primeraVez = arg0
    nombreInstancia = ARGV[1].chomp
    tipoRestore = arg2
  elsif ARGV.length == 5
    arg0 = ARGV[0].upcase.chomp
    if arg0 != "S" && arg0 != "N"
      puts "Se esperaba que el primer parametro fuera N o S".red
      puts ""
      error = true
    end
    arg2 = ARGV[2].upcase.chomp
    if !(arg2 == "T" || arg2 == "G" || arg2 == "B")
      puts "Se esperaba que el tercer parametro fuera el tipo del restore: T[Todo], G[Git], B[Base de Datos]".red
      puts ""
      error = true
    end
    arg3 = ARGV[3].upcase.chomp
    if arg3 != "S" && arg3 != "N"
      puts "Se esperaba que el cuarto parametro fuera N o S".red
      puts ""
      error = true
    end
    arg4 = ARGV[4].upcase.chomp
    if arg4 != "S" && arg4 != "N"
      puts "Se esperaba que el quinto parametro fuera N o S".red
      puts ""
      error = true
    end
    primeraVez = arg0
    nombreInstancia = ARGV[1].chomp
    tipoRestore = arg2
    respuestaGit = arg3
    correrPruebas = arg4
  end
  if error
    puts ""
    puts "Parametros recibidos:  #{primeraVez} #{nombreInstancia} #{tipoRestore} #{respuestaGit} #{correrPruebas}".blue
    puts ""
    puts "Corrige e intenta nuevamente...".green
    puts ""
    exit(error)
  end
else
  puts ""
  puts ""
  puts "¿Es la primera vez que instalas una instancia en este equipo?[s/n]".green
  primeraVez = gets.chomp.capitalize
  if primeraVez == '' || primeraVez != 'S'
    primeraVez = 'N'
  end
  puts ""
  puts "¿Cuál es el nombre de la instancia? [Ejemplo: https://lowestest.sugarondemand.com -> Nombre de la instancia sería 'lowestest']".green
  nombreInstancia = gets.chomp
  while nombreInstancia.empty?
    puts "Nombre de la instancia, por favor?".green
    nombreInstancia = gets.chomp
  end

  if primeraVez == 'N'
    puts ""
    puts "¿Qué tipo de restauración necesitas? [ T : \"Todo\", G : \"Git\", B : \"Base de Datos\" ]".green
    tipoRestore = gets.chomp.capitalize
    if tipoRestore == ''
      tipoRestore = 'T'
    end

    if tipoRestore == "B"
      puts ""
      puts "¿Necesitas ocupar repositorio Git?[s/n]".green
      respuestaGit = gets.chomp.capitalize

      if respuestaGit == '' || respuestaGit != 'S'
        respuestaGit = 'N'
        correrPruebas = 'N'
      elsif respuestaGit == 'S'
        puts ""
        puts "Después de completar el restore, ¿requieres correr las pruebas?[s/n]".green
        correrPruebas = gets.chomp.capitalize
        if correrPruebas == '' || correrPruebas != 'S'
          correrPruebas = 'N'
        end
      end
    elsif tipoRestore == 'G' || tipoRestore == 'T'
      respuestaGit = 'S'
      puts ""
      puts "Después de completar el restore, ¿requieres correr las pruebas?[s/n]".green
      correrPruebas = gets.chomp.capitalize
      if correrPruebas == '' || correrPruebas != 'S'
        correrPruebas = 'N'
      end
    end
  else
    tipoRestore = 'T'
    respuestaGit = 'S'
    puts ""
    puts "Después de completar el restore, ¿requieres correr las pruebas?[s/n]".green
    correrPruebas = gets.chomp.capitalize
    if correrPruebas == '' || correrPruebas != 'S'
      correrPruebas = 'N'
    end
  end
end
restore = RestoreInstanciaVagrant.new(primeraVez, nombreInstancia, tipoRestore, respuestaGit, correrPruebas)
