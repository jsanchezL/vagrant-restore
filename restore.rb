#!/usr/bin/env ruby

require 'rubygems'
require 'json'
require 'rbconfig'
require 'fileutils'
require 'colorize'
require 'thread'

class RestoreInstanciaVagrant
  @@os = nil
  @@diccionario = "dictionary-instancias-merx.json"
  @@gitMERX = nil
  @@primeraVez = nil
  @@data_hash = nil
  @@nombreInstancia = nil
  @@nombreAliasInstancia = nil
  @@paramsInstancia = nil
  @@dir_instancia = nil
  @@dir_scriptrb = nil
  @@origenParams = nil
  @@EsSugar7 = nil

  def initialize(origenParams, primeraVez, nombreInstancia, tipoRestore, respuestaGit, correrPruebas)
    os
    @@dir_scriptrb = Dir.pwd
    @@origenParams = origenParams
    @@primeraVez = primeraVez
    leerDiccionario(nombreInstancia)
    procesar(tipoRestore,respuestaGit,correrPruebas)
  end

  #Carga el diccionario de datos y los parámetros para ejecutar el script
  def leerDiccionario(nombreInstancia)
    file = File.read(@@diccionario)
    @@data_hash = JSON.parse(file)
    instancias = @@data_hash["instancias-merx"]
    @@paramsInstancia = instancias["#{nombreInstancia}"]
    if @@paramsInstancia.nil?
      ingresarNombreDeLaInstanciaNuevamente
    else
      if @@paramsInstancia['alias'] == '' || @@paramsInstancia['alias'] == nombreInstancia
        @@nombreInstancia = nombreInstancia
        @@nombreAliasInstancia = @@nombreInstancia
      else
        @@nombreInstancia = nombreInstancia
        @@nombreAliasInstancia = @@paramsInstancia['alias']
      end

      if @@paramsInstancia['version'].to_i < 7710
        @@EsSugar7 = 7
      elsif @@paramsInstancia['version'].to_i < 7900
        @@EsSugar7 = 8
      elsif @@paramsInstancia['version'].to_i >= 7900 and @@paramsInstancia['version'].to_i < 71000
        @@EsSugar7 = 9
      else
        @@EsSugar7 = 10
      end
    end
  end

  def ingresarNombreDeLaInstanciaNuevamente
    if !@@origenParams
      puts "====> ¡No existe instancia con ese nombre! - Revisa tus datos e ingresa de nuevo el nombre de la instancia a restaurar:".red
      nombreInstancia = gets.chomp
      leerDiccionario(nombreInstancia)
    else
      puts "====> ¡No existe instancia con ese nombre! - Revisa tus datos e ingresa de nuevo el nombre correcto de la instancia a restaurar".red
      puts ""
      puts "Corrige e intenta nuevamente...".green
      puts ""
      exit(true)
    end
  end

  def procesar(tipoRestore, respuestaGit, correrPruebas)
    tiempoDeInicio = Time.new.to_i
    puts ""
    puts "==> Iniciando...".green
    if @@primeraVez != 'S'
      if tipoRestore == 'T' || tipoRestore == 'O'
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
    if tipoRestore == 'T' || tipoRestore == 'O' #Todo
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
          instalarPaquetes
          repararInstancia
          ejecutarPruebas
        else
          recordatorioDeInstalacionComposerYnpm
          instalarPaquetes
          repararInstancia
        end
      end
    elsif tipoRestore == 'G' #Sólo git
      obtenerCambiosDeGit
      if correrPruebas == 'S'
        instalarComposerYnpm
        instalarPaquetes
        repararInstancia
        ejecutarPruebas
      else
        recordatorioDeInstalacionComposerYnpm
        instalarPaquetes
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
          instalarPaquetes
          repararInstancia
          ejecutarPruebas
        else
          recordatorioDeInstalacionComposerYnpm
          instalarPaquetes
          repararInstancia
        end
      else
        recordatorioDeInstalacionComposerYnpm
        instalarPaquetes
        repararInstancia
      end
    end
    tiempoDeFin = Time.new.to_i
    tiempoDeProceso = ( tiempoDeFin - tiempoDeInicio ) / 60

    puts "==> Terminando...".green
    puts " "
    puts "==> Finalizado en #{tiempoDeProceso} mins.".green
  end

  def instalarVagrantBoxEnEquipo
    Dir.chdir("#{@@data_hash['vagrant']['dir_base']}/#{@@EsSugar7}")
    puts " "
    puts "==> Instalando Vagrant Box...".green
    case @@EsSugar7
    when 7
      system("vagrant init mmarum/sugar7-php54")
    when 8
      system("vagrant init mmarum/sugar7-php56")
    when 9
      system("vagrant init sugarcrm/php71")
    when 10
      system("vagrant init sugarcrm/php71es54")
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
        if !@@origenParams
          puts "====> ¡Se detecto que tienes más de un backup en ese directorio! - Por favor selecciona el más reciente:".yellow
          nombreBackup = seleccionarBackup(rutaBackup)
        else
          puts ""
          puts "====> ¡Se detecto que tienes más de un backup en ese directorio! - Por favor elimina los antiguos y deja el más reciente".red
          puts ""
          puts "Corrige e intenta nuevamente...".green
          puts ""
          exit(true)
        end
      else
        nombreBackup = "*.tar.gz"
      end

      if @@os == "linux" || @@os == "mac"
        limpiarDirectorio(File.join(rutaBackup,@@nombreAliasInstancia+'*'))
        result = system("tar -zxf #{nombreBackup}")
      elsif @@os == "win"
        nombreBackupTar = "*.tar"
        carpetaAnterior = File.join(rutaBackup,@@nombreAliasInstancia+'*').gsub(%r{\\}) {'/'}
        archivoTar = File.join(rutaBackup,@@nombreAliasInstancia+nombreBackupTar).gsub(%r{/}) {'\\'}
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
      if !@@origenParams
        ingresarRutaDelBackupManualmente
      else
        puts ""
        puts "====> ¡No se encontró ruta del Backup!".red
        puts ""
        puts "====> Revisa la llave \"dir_backup\" del diccionario de datos y verifica manualmente que exista el directorio,".red
        puts "====> en caso de que \"dir_backup\" este vacío, por favor comprueba que exista la siguiente ruta:".red
        rutaBackup = Dir.pwd + "/proyectos/" + @@nombreAliasInstancia + "/backups/lastest"
        puts ""
        puts "#{rutaBackup}".red
        puts ""
        puts "Si no existe la ruta, crear y copiar el archivo del último backup ahí".red
        puts ""
        puts "Intenta nuevamente...".green
        puts ""
        exit(true)
      end
    end
  end

  def limpiarInstancia(ruta)
    puts " "
    puts "==> Limpiando la instancia...".green
    restore = File.join(ruta,@@nombreAliasInstancia+'*')
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
    elsif existe_directorio(Dir.glob("#{restore}/#{@@nombreAliasInstancia}*").select{ |file| !File.file?(file) }[0]) #instancias que no provengan de sugarondemand.com
      instanciaDir = Dir.glob("#{restore}/#{@@nombreAliasInstancia}*").select{ |file| !File.file?(file) }[0]
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
    restore = File.join(ruta,@@nombreAliasInstancia+'*')
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
        system("attrib #{@@data_hash['vagrant']['dir_base']}/#{@@EsSugar7} /S /D -S -A -R -I")
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
      rutaw = File.join(restore,@@nombreAliasInstancia+'*')
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
    Dir.chdir("#{@@data_hash['vagrant']['dir_base']}/#{@@EsSugar7}")
    if @@os != 'win'
      res = `curl -I -s -L http://localhost:8080 | grep 'HTTP/1.1'`
      if !res.include? "200"
        puts " "
        puts "==> Iniciando vagrant...".green
        system("vagrant reload")
      end
    else
      res = `ping 192.168.33.10`
      if res.include? "agotado"
        puts " "
        puts "==> Iniciando vagrant...".green
        system("vagrant reload")
      end
    end
  end

  def restaurarBDs
    puts " "
    puts "==> Restaurando bases de datos...".green
    system("vagrant ssh -c \"mysql -u root -proot -e 'drop database IF EXISTS #{@@nombreInstancia}; create database #{@@nombreInstancia}; show databases;'\"")
    if @@paramsInstancia['esOndemand']
      @s = Spinner.new()
      while !system("vagrant ssh -c \"mysql -u root -proot #{@@nombreInstancia} < /vagrant/#{@@nombreInstancia}.merxbp.loc/*#{@@paramsInstancia['edicion']}.sql\"") do
        sleep 0.5
      end
      @s.stop("done...")
      system("vagrant ssh -c \"mysql -u root -proot #{@@nombreInstancia} < /vagrant/#{@@nombreInstancia}.merxbp.loc/*#{@@paramsInstancia['edicion']}_triggers.sql\"")
    else
      @s = Spinner.new()
      while !system("vagrant ssh -c \"mysql -u root -proot #{@@nombreInstancia} < /vagrant/#{@@nombreInstancia}.merxbp.loc/*.sql\"") do
        sleep 0.5
      end
      @s.stop("done...")
    end
    puts ""
    puts "===> Origin copia de respaldo de la bd".green
    system("vagrant ssh -c \"mysql -u root -proot -e 'drop database IF EXISTS #{@@nombreInstancia}_origin; create database #{@@nombreInstancia}_origin; show databases;'\"")
    if @@paramsInstancia['esOndemand']
      @s = Spinner.new()
      while !system("vagrant ssh -c \"mysql -u root -proot #{@@nombreInstancia}_origin < /vagrant/#{@@nombreInstancia}.merxbp.loc/*#{@@paramsInstancia['edicion']}.sql\"") do
        sleep 0.5
      end
      @s.stop("done...")
      system("vagrant ssh -c \"mysql -u root -proot #{@@nombreInstancia}_origin < /vagrant/#{@@nombreInstancia}.merxbp.loc/*#{@@paramsInstancia['edicion']}_triggers.sql\"")
    else
      @s = Spinner.new()
      while !system("vagrant ssh -c \"mysql -u root -proot #{@@nombreInstancia}_origin < /vagrant/#{@@nombreInstancia}.merxbp.loc/*.sql\"") do
        sleep 0.5
      end
      @s.stop("done...")
    end
  end

  def ejecutarScripts
    if !@@paramsInstancia['db_scripts'].empty?
      puts " "
      puts "==> Ejecutando scripts de base de datos...".green
      scripts = @@paramsInstancia['db_scripts']
      scripts.each_index do |i|
        if @@os == "win"
          comando = "vagrant ssh -c \"mysql -u root -proot #{@@nombreInstancia} -e '#{scripts[i]}'\""
        else
          comando = "vagrant ssh -c 'mysql -u root -proot #{@@nombreInstancia} -e \"#{scripts[i]}\"'"
          puts "#{comando}"
        end
        system(comando)
      end
    end
  end

  def instalarPaquetes
    if !@@paramsInstancia['packages'].empty?
      if File.exist?(File.join(@@dir_instancia,"cliModuleInstall.php"))
        puts " "
        puts "==> Instalando paquetes...".green
        paquetes = @@paramsInstancia['packages']
        paquetes.each_index do |i|
          if @@os == "win"
            dir_paquetes = File.join(@@dir_instancia,"upload").gsub(%r{/}) {'\\'}
            FileUtils.cp paquetes[i].gsub(%r{/}) {'\\'}, dir_paquetes
          else
            dir_paquetes = File.join(@@dir_instancia,"upload")
            FileUtils.cp paquetes[i], dir_paquetes
          end
          name_paquete = File.basename(paquetes[i]);
          @s = Spinner.new()
          while !system("vagrant ssh -c\"cd /vagrant/#{@@nombreInstancia}.merxbp.loc;php cliModuleInstall.php -i /vagrant/#{@@nombreInstancia}.merxbp.loc -z /vagrant/#{@@nombreInstancia}.merxbp.loc/upload/#{name_paquete}\"") do
            sleep 0.5
          end
        end
        @s.stop("done...")
        if existe_directorio?(File.join(@@dir_instancia,".git"))
          puts " "
          puts "====> ¡Recuerda, después de instalar paquetes, verifica el estado de tus archivos con: ".red
          puts "========> cd #{@@dir_instancia}; git status;".red
        end
      end
    end
  end

  def cambiarPermisos
    puts " "
    puts "==> Cambiando permisos a los archivos de la instancia...".green
    @s = Spinner.new()
    while !system("vagrant ssh -c \"chmod 755 -R /vagrant/#{@@nombreInstancia}.merxbp.loc\"") do
      sleep 0.5
    end
    @s.stop("done...")
  end

  def installComposer
    @@dir_instancia = obtenerRutaInstancia
    install_composer = false
    dir_composer = File.join(@@dir_instancia,"vendor/composer/composer")
    if !existe_directorio?(dir_composer)
      install_composer = true
    end
    return install_composer
  end

  def installNpm
    install_npm = false

    # if @@EsSugar7 >= 8 && @@EsSugar7 < 10
      dir_npm = File.join(@@dir_instancia,"node_modules")
    # end #falta caso para sugar 7.10 o superior

    if !existe_directorio?(dir_npm)
      install_npm = true
    end
    return install_npm
  end

  def instalarComposerYnpm

    if @@EsSugar7 < 10
      jsTester = 'npm'
    else
      jsTester = 'yarn'
    end

    if installComposer && installNpm
      puts " "
      puts "==> Instalando composer y #{jsTester}...".green
      t1 = Thread.new{
        if @@EsSugar7 >= 10
          system("vagrant ssh -c \"cd /vagrant/#{@@nombreInstancia}.merxbp.loc; rm composer.lock\"")
          system("vagrant ssh -c \"sudo service apache2 restart\"")
        end
        system("vagrant ssh -c \"cd /vagrant/#{@@nombreInstancia}.merxbp.loc; composer install\"")
        puts ""
        puts "======> ¡Instalado composer!".green
        puts ""
      }
      t2 = Thread.new{
        system("vagrant ssh -c \"cd /vagrant/#{@@nombreInstancia}.merxbp.loc; #{jsTester} install\"")
        puts ""
        puts "======> ¡Instalado #{jsTester}!".green
        puts ""
      }
      t1.join
      t2.join
    elsif installComposer
      puts " "
      puts "==> Instalando composer...".green
      if @@EsSugar7 >= 10
        system("vagrant ssh -c \"cd /vagrant/#{@@nombreInstancia}.merxbp.loc; rm composer.lock\"")
        system("vagrant ssh -c \"sudo service apache2 restart\"")
      end
      system("vagrant ssh -c \"cd /vagrant/#{@@nombreInstancia}.merxbp.loc; composer install\"")
      puts ""
      puts "======> ¡Instalado composer!".green
      puts ""
    elsif installNpm
      puts " "
      puts "==> Instalando #{jsTester}...".green
      system("vagrant ssh -c \"cd /vagrant/#{@@nombreInstancia}.merxbp.loc; #{jsTester} install\"")
      puts ""
      puts "======> ¡Instalado #{jsTester}!".green
      puts ""
    end
  end

  def recordatorioDeInstalacionComposerYnpm
    if @@EsSugar7 < 10
      jsTester = 'npm'
    else
      jsTester = 'yarn'
    end

    if installComposer && installNpm
      puts " "
      puts "====> ¡Recuerda antes de correr tus pruebas, instala composer y #{jsTester}, desde el directorio vagrant con las siguientes lineas! : ".red
      if @@EsSugar7 >= 10
        puts "========> vagrant ssh -c \"cd /vagrant/#{@@nombreInstancia}.merxbp.loc; rm composer.lock\"".red
        puts "========> vagrant ssh -c \"sudo service apache2 restart\"".red
      end
      puts "========> vagrant ssh -c 'cd /vagrant/#{@@nombreInstancia}.merxbp.loc; composer install'".red
      puts "========> vagrant ssh -c 'cd /vagrant/#{@@nombreInstancia}.merxbp.loc; #{jsTester} install'".red
    elsif installComposer
      puts " "
      puts "====> ¡Recuerda antes de correr tus pruebas, instala composer, desde el directorio vagrant con la siguiente linea! : ".red
      if @@EsSugar7 >= 10
        puts "========> vagrant ssh -c \"cd /vagrant/#{@@nombreInstancia}.merxbp.loc; rm composer.lock\"".red
        puts "========> vagrant ssh -c \"sudo service apache2 restart\"".red
      end
      puts "========> vagrant ssh -c 'cd /vagrant/#{@@nombreInstancia}.merxbp.loc; composer install'".red
    elsif installNpm
      puts " "
      puts "====> ¡Recuerda antes de correr tus pruebas, instala #{jsTester}, desde el directorio vagrant con la siguiente linea! : ".red
      puts "========> vagrant ssh -c 'cd /vagrant/#{@@nombreInstancia}.merxbp.loc; #{jsTester} install'".red
    end
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
      system("git fetch origin")
      res = `git branch`
      exp = /\*\s#{@@paramsInstancia['branch']}/
      if !exp.match(res)
        system("git checkout -b #{@@paramsInstancia['branch']} origin/#{@@paramsInstancia['branch']}")
      else
        system("git checkout #{@@paramsInstancia['branch']}")
      end
      system("git merge origin/#{@@paramsInstancia['branch']}")
    else
      puts " "
      puts "==> Creando repositorio local de MerxBP...".green
      Dir.chdir(@@data_hash['github']['local']['dir'])
      system("git clone #{@@gitMERX}")
      Dir.chdir(gitLocal)
      res = `git branch`
      exp = /\*\s#{@@paramsInstancia['branch']}/
      if !exp.match(res)
        system("git checkout -b #{@@paramsInstancia['branch']} origin/#{@@paramsInstancia['branch']}")
      else
        system("git checkout #{@@paramsInstancia['branch']}")
      end
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
    system("git config core.fileMode false")
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
    #añadiendo cosas utiles para atom
    system("git config atom.open-on-github.remote origin")
    system("git config atom.open-on-github.branch #{@@paramsInstancia['branch']}")
    system("git config --global user.name \"#{@@data_hash["github"]["name"]}\"")
    system("git config --global user.email #{@@data_hash["github"]["email"]}")
  end

  def repararInstancia
    Dir.chdir("#{@@data_hash['vagrant']['dir_base']}/#{@@EsSugar7}")
    repair = "#{@@data_hash['vagrant']['dir_base']}/#{@@EsSugar7}/#{@@nombreInstancia}.merxbp.loc/repair.php"
    if File.exist?(repair)
      puts " "
      puts "==> Reparando la instancia...".green
      @s = Spinner.new()
      while !system("vagrant ssh -c \"cd /vagrant/#{@@nombreInstancia}.merxbp.loc; php repair.php\"") do
        sleep 0.5
      end
      @s.stop("done...")
    else
      puts " "
      puts "==> No se puedo reparar la instancia por falta del archivo repair.php, hacerlo de forma manual...".red
    end
    puts " "
  end

  def ejecutarPruebas
    puts " "
    puts "==> Ejecutando las pruebas PHP...".green
    if @@EsSugar7 < 10
      system("vagrant ssh -c \"cd /vagrant/#{@@nombreInstancia}.merxbp.loc/tests; ../vendor/phpunit/phpunit/phpunit\"")
    else
      system("vagrant ssh -c \"cd /vagrant/#{@@nombreInstancia}.merxbp.loc/tests/{old}; ../../vendor/bin/phpunit\"")
    end
    puts " "
    puts "==> Ejecutando las pruebas JS...".green
    if @@EsSugar7 < 8
      system("vagrant ssh -c \"cd /vagrant/#{@@nombreInstancia}.merxbp.loc/tests; grunt karma:ci\"")
    elsif @@EsSugar7 >= 8 && @@EsSugar7 < 10
      system("vagrant ssh -c \"cd /vagrant/#{@@nombreInstancia}.merxbp.loc/node_modules/gulp/bin/gulp.js karma --ci\"")
    # else aquí va el caso de de sugar 7.10 o superior
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
      return Dir.pwd + "/proyectos/" + @@nombreAliasInstancia + "/backups/lastest"
    end
  end

  def obtenerRutaInstancia
    @@data_hash['vagrant']['dir_base'] + "/" + @@EsSugar7.to_s + "/" + @@nombreInstancia + ".merxbp.loc"
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
      if @@os == "win"
        dirRepo = dirRepo.gsub(%r{\\}) {'/'}
        gitignore = File.join(@@dir_instancia,".gitignore").gsub(%r{/}) {'\\'}
        system("del /Q #{gitignore}")
      else
        File.delete(File.join(@@dir_instancia,".gitignore"))
      end
      limpiarDirectorio(dirRepo)
    end
  end
end

class Spinner

  GLYPHS = %w[| / – \\ | / – \\]

  def initialize(msg = nil)
    print "#{msg}... " unless msg.nil?
    @thread = Thread.new do
      while true
        GLYPHS.each do |glyph|
          print "\b#{glyph}"
          sleep 0.10
        end
      end
    end
  end

  def stop(msg = nil)
    @thread.exit
    print  "\b#{msg}\n"
  end

end


error = false
origenParams = false

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

if ARGV.length != 0
  if ARGV.length == 1
    puts "Se esperaba al menos 2 parámetros para iniciar el proceso".red
    puts ""
    error = true
    primeraVez = ARGV[0].upcase.chomp
  elsif ARGV.length == 2
    arg0 = ARGV[0].upcase.chomp
    if arg0 != "N" && arg0 != "S"
      puts "Se esperaba que el primer parámetro fuera N o S".red
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
    if arg0 != "N" && arg0 != "S"
      puts "Se esperaba que el primer parámetro fuera N o S".red
      puts ""
      error = true
    end
    arg2 = ARGV[2].upcase.chomp
    # Agregando opción para restore back original
    if arg2 == "T" || arg2 == "G" ||  arg2 == "B" || arg2 == "O"
      if arg2 == "T"
        respuestaGit = 'S'
        correrPruebas = 'S'
      elsif arg2 == "B" || arg2 == "O"
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
      puts "Se esperaba que el tercer parámetro fuera el tipo del restore: T[Todo], G[Git], B[Base de Datos]".red
      puts ""
      error = true
    end
  elsif ARGV.length == 4
    arg0 = ARGV[0].upcase.chomp
    if arg0 != "N" && arg0 != "S"
      puts "Se esperaba que el primer parámetro fuera N o S".red
      puts ""
      error = true
    end
    arg2 = ARGV[2].upcase.chomp
    if !(arg2 == "T" || arg2 == "G" || arg2 == "B" || arg2 == "O")
      puts "Se esperaba que el tercer parámetro fuera el tipo del restore: T[Todo], G[Git], B[Base de Datos], O[Original]".red
      puts ""
      error = true
    end
    arg3 = ARGV[3].upcase.chomp
    if arg3 != "N" && arg3 != "S"
      puts "Se esperaba que el cuarto parámetro fuera N o S".red
      puts ""
      error = true
    end
    if arg3 == "S"
      respuestaGit = arg3
      correrPruebas = 'N'
    else
      if arg2 == "G"
        respuestaGit = 'S'
      else
        respuestaGit = 'N'
      end
      correrPruebas = 'N'
    end
    primeraVez = arg0
    nombreInstancia = ARGV[1].chomp
    tipoRestore = arg2
  elsif ARGV.length == 5
    arg0 = ARGV[0].upcase.chomp
    if arg0 != "N" && arg0 != "S"
      puts "Se esperaba que el primer parámetro fuera N o S".red
      puts ""
      error = true
    end
    arg2 = ARGV[2].upcase.chomp
    if !(arg2 == "T" || arg2 == "G" || arg2 == "B" || arg2 == "O")
      puts "Se esperaba que el tercer parámetro fuera el tipo del restore: T[Todo], G[Git], B[Base de Datos], O[Original]".red
      puts ""
      error = true
    end
    arg3 = ARGV[3].upcase.chomp
    if arg3 != "N" && arg3 != "S"
      puts "Se esperaba que el cuarto parámetro fuera N o S".red
      puts ""
      error = true
    end
    arg4 = ARGV[4].upcase.chomp
    if arg4 != "N" && arg4 != "S"
      puts "Se esperaba que el quinto parámetro fuera N o S".red
      puts ""
      error = true
    end
    primeraVez = arg0
    nombreInstancia = ARGV[1].chomp
    tipoRestore = arg2
    if arg2 == "G"
      respuestaGit = 'S'
    else
      respuestaGit = arg3
    end
    correrPruebas = arg4
  end
  if error
    puts ""
    puts "parámetros recibidos:  #{primeraVez} #{nombreInstancia} #{tipoRestore} #{respuestaGit} #{correrPruebas}".blue
    puts ""
    puts "Corrige e intenta nuevamente...".green
    puts ""
    exit(error)
  else
    origenParams = true
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
    puts "¿Qué tipo de restauración necesitas? [ T : \"Todo\", G : \"Git\", B : \"Base de Datos\", O : \"Original\" ]".green
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
    elsif tipoRestore == 'O'
      respuestaGit = 'N'
      correrPruebas = 'N'
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
restore = RestoreInstanciaVagrant.new(origenParams, primeraVez, nombreInstancia, tipoRestore, respuestaGit, correrPruebas)
