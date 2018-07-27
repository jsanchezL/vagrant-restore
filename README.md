# vagrant-restore

Permite instalar o restaurar instancias de SugarCRM 7.x ondemand u onsite en un Vagrant box para trabajar de forma local
en el desarrollo de personalizaciones del CRM, seguimiento a bugs levantados en el portal de casos, o simplemente probar algún
sabor de Sugar.

El programa fue desarrollado en ruby, para tener soporte en los 3 principales SO (Mac OS X, GNU/Linux, Windows 7, 8, 10)

## prerequisitos

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

En Mac OS X, se corren las siguientes lineas:

```sh
  which gem
  sudo gem update --system
  sudo gem install json
  sudo gem install colorize
```

En GNU/Linux se hace algo parecido que en Mac OS X, con excepción de la primera linea.

## dictionary-instancias-merx

Es un archivo json en el cual reside las configuraciones para los restores. La estructura es la siguiente:
* instancias-merx
  * nombreInstancia
    * alias
    * esOndemand
    * urlOnSite
    * edicion
    * db_host_name
    * db_user_name
    * db_password
    * db_name
    * host_elastic
    * db_scripts
    * dir_backup
    * branch
    * version
    * dir_packages
    * packages
* vagrant
  * dir_base
* cliModuleInstall
* github
  * user
  * name
  * email
  * local
    * dir
    * remote
* nginx
  * dir_base
  * dir

## ejecución

El programa tiene 2 modos de ejecutarse, el primero es por parametros y el segundo de forma interactiva.

### parametrizado

Este modo tiene las siguientes opciones:
* primeraVez (S/N) - Se refiere a si la instalación o restore es completamente nuevo en el equipo anfitrión.
* nombreInstancia - Nombre del proyecto a restaurar o instalar en el vagrant box
* tipoRestore [T(Todo), G(git), B(Base de Datos)] - La opción T(Todo) se ocupa para hacer un restore de base de datos, obtener una copia del repositorio git, instalar devtools(composer, npm), paquetes de personalizaciones, y correr pruebas unitarias de PHP y JS. G(git) se ocupa para restarurar la rama o cambiar, se tiene algún riesgo de colisionar entre ramas por lo cual se debe ocupar con cuidado. B(Base de Datos) restaura la base de datos y se instalan los paquetes de personalizaciones que se necesiten.
* respuestaGit (S/N)
* correrPruebas (S/N)

```sh
ruby restore.rb (S/N) nombreInstancia [tipoRestore, respuestaGit, correrPruebas]
```
