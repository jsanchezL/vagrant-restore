# Vagrant-restore

Permite instalar o restaurar instancias de SugarCRM 7.x ondemand u onsite en un Vagrant box para trabajar de forma local
en el desarrollo de personalizaciones del CRM, seguimiento a bugs levantados en el portal de casos, o simplemente probar algún
sabor de Sugar.

El programa fue desarrollado en ruby, para tener soporte en los 3 principales SO (Mac OS X, GNU/Linux, Windows 7, 8, 10)

## Prerequisitos

Para los 3 SO se deberá contar con la instalación y correcta configuración de:
* virtualbox
* vagrant
* nginx
* ruby
* git
* ssh client
* 7zip - Sólo para Windows

En Windows, se necesitan poner a nginx y 7zip como variables de entorno antes de arrancar el script, también se requiere actualizar gems con el siguiente comando:

```sh
  gem install rubygems-update
```

E instalar posiblemente las gems json y colorize

```sh
  gem install json
  gem install colorize
```

En Mac OS X, se pude utilizar instalar [Homebrew][989d06d7] y se corren las siguientes lineas:

  [989d06d7]: https://brew.sh/ "brew"

```sh  
  brew install rbenv
  rbenv install 2.5.1
  which gem
  sudo gem update --system
  sudo gem install json
  sudo gem install colorize
```

En GNU/Linux se hace algo parecido que en Mac OS X, con excepción de las 2 primera línea. Para más información pudes consultar la [Guía para instalar ruby][21f64003]

  [21f64003]: https://gorails.com/setup "Instalar Ruby"

## Dictionary-instancias-merx

Es un archivo json en el cual residen las configuraciones para los restores. La estructura es la siguiente:
* instancias-merx
  * **nombreInstancia** - Nombre de la instancia. Por ejemplo: "lowes"
    * **alias** - Alias con el cual podemos desplegarla la instancia. Por ejemplo: "lowesqa"
    * **esOndemand** - "true|false"
    * **urlOnSite** - Si la instancia no es ondemand se especifica la url a buscar dentro de los archivos config.php y .htaccess
    * **edicion** - "ent|pro"
    * **db_host_name** - Url del servidor en donde esta la base de datos en ondemand | onsite (Examinar config.php del backup)
    * **db_user_name** - Usuario que se ocupa para ingresar a la base de datos (Examinar config.php del backup)
    * **db_password** - Contraseña que se emplea para el ingreso a la base de datos (Examinar config.php del backup)
    * **db_name** - Nombre de la base de datos (Examinar config.php del backup)
    * **host_elastic** - Url del servidor en donde corre Elastic Search en ondemand | onsite (Examinar config.php del backup)
    * **db_scripts** - Array de instrucciones SQL, si no se especifican no son consideradas.
    * **dir_backup** - Directorio donde se ubican los backups de la instancia. Por ejemplo: /home/usuario/merx/proyectos/lowes/backups/lastest
    * **branch** - Rama de github dentro del repositorio de custom_sugarcrm de merx
    * **version** - Versión de Sugar, ejemplo: para la versión 8.0.0 será convertida así 80000.
    * **dir_packages** - Directorio donde se encuentran los paquetes de personalizaciones. Por ejemplo: /home/usuario/merx/repos/sugarcrm_packages
    * **packages** - Array con los nombres de los paquetes a ser considerados para construirlos e instalarlos en la instancia, si no se especifican no son considerados.
* vagrant
  * **dir_base** - Directorio donde se encuentra instalado el box de vagrant en nuestro sistema. Por ejemplo: /home/usuario/merx/vagrant/sugar_env/sugar
  * **multiversionSugar** - "false|true" Es una opción para soportar varias versiones de sugar en un mismo box de vagrant.
* **cliModuleInstall** - Ruta del archivo para instalar paquetes por medio de linea de comandos. Por ejemplo: /home/usuario/merx/repos/vagrant-restore/cliModuleInstall.php
* github
  * **user** - Usuario de github
  * **name** - Nombre completo que esta en tu perfil de github
  * **email** - Email con el cual te diste de alta en github
  * local
    * **dir** - Directorio donde se encontrará una copia local del repositorio custom_sugarcrm de MerxBP. Ejemplo: /home/usuario/merx/repos
    * **remote** - Repositorio de github. Ejemplo: git@github.com:MerxBusinessPerformance/custom_sugarcrm.git
  * paquetes
    * **dir** - Directorio donde se encontrará una copia local del repositorio sugarcrm_packages de MerxBP. Ejemplo: /home/usuario/merx/repos
    * **remote** - Repositorio de github. Ejemplo: git@github.com:MerxBusinessPerformance/sugarcrm_packages.git
* nginx - Aún en fase experimental.
  * **dir_base**
  * **dir**

## Ejecución

El programa tiene 2 modos de ejecutarse, el primero es por parámetros y el segundo de forma interactiva.

Se puede ejecutar como un script shell sólo tenemos que darle permisos de ejecución.

```sh
chmod +x restore.rb
```

### Parametrizado

```sh
ruby restore.rb primeraVez nombreInstancia [tipoRestore, respuestaGit, correrPruebas]
./restore.rb primeraVez nombreInstancia [tipoRestore, respuestaGit, correrPruebas]
```

Este modo tiene las siguientes opciones:
* primeraVez (s/n)
  - La respuesta "s" se refiere a que es una instancia totalmente nueva y se debe instalar desde 0 en el equipo anfitrión.
  - La respuesta "n" es que se tiene un vagrant box previamente instalado que es compatible con la instancia a restaurar.
* nombreInstancia - Nombre del proyecto a restaurar o instalar en el vagrant box
* tipoRestore [T, G, B, O] - Es opcional por default sera T
  - T (Todo) se ocupa para hacer un restore de base de datos, obtener una copia del repositorio git, instalar devtools(composer, npm), paquetes de personalizaciones, y correr pruebas unitarias de PHP y JS.
  - G (git) se ocupa para restaurar la rama o cambiar, se tiene algún riesgo de colisionar entre ramas por lo cual se debe ocupar con cuidado.
  - B (Base de Datos) restaura la base de datos y se instalan los paquetes de personalizaciones que se necesiten.
  - O (Original) sirve para instalar una instancia sin paquetes, sin pruebas, sin repositorio git.
* respuestaGit (s/n) - Es opcional por default será N
  - Con la respuesta "s" se intenta descargar los últimos cambios de la rama github que se haya especificado en la configuración del
  - Con la respuesta "n" se descarta la actualización de archivos desde github
* correrPruebas (s/n) - Es opcional por default será N
  - Con una respuesta afirmativa "s" se intentará ejecutar las pruebas unitarias de PHP y JS
  - Con una respuesta negativa "n" se omite la ejecución sin embargo nos dará un mensaje de recordatorio por si queremos mas adelante ejecutar dichas pruebas de forma manual.

##### ejemplos de uso

Queremos restaurar una instancia ondemand del proyecto ruhrpumpen de forma total con los últimos cambios de github de ese proyecto y sin correr prueba unitarias.

```sh
ruby restore.rb n ruhrpumpen t s n
./restore.rb n ruhrpumpen t s n
```

Queremos restaurar solamente la base de datos de una instancia ondemand del proyecto ruhrpumpen sin descargar los últimos cambios de github de ese proyecto y sin correr prueba unitarias.

```sh
ruby restore.rb n ruhrpumpen b
./restore.rb n ruhrpumpen b
```

### Interactivo

En esta opción se nos depliega un serie de preguntas en la terminal o consola que nos guian por el proceso.

```sh
ruby restore.rb
./restore.rb
```
