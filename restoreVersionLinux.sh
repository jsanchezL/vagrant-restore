#! /bin/bash
homeProyBkUp=""
proyecto=""
db_password=""
dirVagrant=""
primeraVez=""
nameBranch=""
responseGitStatus=""
responseVagrant=""
userGit=""
correrPruebas=""
esOndemand=""
urlOnSite=""
db_host_name=""
db_user_name=""
db_name=""
host_elastic=""
gitMERX="git@github.com:MerxBusinessPerformance/custom_sugarcrm.git"
now=$(date +"%Y-%m-%d")
time=$(date +"%T")

clear

#El orden de los parametros son:
primeraVez=$1
proyecto=$2
dirVagrant=$3
nameBranch=$4
userGit=$5
correrPruebas=$6

esOndemand=$7
urlOnSite=$8
db_host_name=$9
db_user_name=${10}
db_password=${11}
db_name=${12}
host_elastic=${13}

echo " "
echo "Restaurando Instancia ${proyecto} en Local..."
echo " "

homeProyBkUp="${PWD}/proyectos/$proyecto/backups/lastest"

if [ -d $homeProyBkUp ]; then
	echo " "
	echo "Inicio del proceso ${now} - ${time}......."
	cd $homeProyBkUp
	#Debe de haber un solo archivo de backup, el más reciente...
	if [ "$(ls -1 ${PWD} | wc -l)" -eq 1 ]; then
		#Descomprime la versión más actual de la instancia ondemand
		tar -xzf *.tar.gz
		#Borrando cache y upload de la instancia ondemand
		echo " "
		echo "Limpiando la instancia..."
		rm -rf $proyecto*/*ent/cache/*
		rm -rf $proyecto*/*ent/upload/*
		rm -f $proyecto*/*log

		echo " "
		echo "Configurando la instancia..."
		#Cambio de Mysql en db-host, user, pwd y db
		sed -i "s/${db_host_name}/localhost/g" $proyecto*/*ent/config.php
		#Usuario u_nombre_proyecto
		sed -i "s/${db_user_name}/root/g" $proyecto*/*ent/config.php
		#pwd de mysql
		sed -i "s/${db_password}/root/g" $proyecto*/*ent/config.php
		#db_nombre_proyecto
		sed -i "s/${db_name}/${proyecto}/g" $proyecto*/*ent/config.php

		if [ $esOndemand == 'S' ]; then
			#Cambio de host_name
			sed -i "s/${proyecto}.sugarondemand.com/${proyecto}.merxbp.loc/g" $proyecto*/*ent/config.php
		else
			#Cambio de host_name
			sed -i "s/${urlOnSite}/${proyecto}.merxbp.loc/g" $proyecto*/*ent/config.php
		fi

		#Cambio de Elastic-host
		sed -i "s/${host_elastic}/localhost/g" $proyecto*/*ent/config.php
		#Cambio en .htaccess
		sed -i "s/RewriteBase \//RewriteBase \/sugar\/${proyecto}.merxbp.loc\//g" $proyecto*/*ent/.htaccess
		#Configuramos el backup triggers sql de db_nombre_proyecto a proyecto
		sed -i "s/${db_name}/${proyecto}/g" $proyecto*/*ent.sql
		sed -i "s/${db_name}/${proyecto}/g" $proyecto*/*ent_triggers.sql

		if [ -d $dirVagrant/$proyecto.merxbp.loc ]; then

			#eliminamos toda la carpeta de la instancia local despues de haber hecho un merge de los cambios en local al repo
			rm -rf $dirVagrant/$proyecto.merxbp.loc

			#regresamos a dir de backup
			cd $homeProyBkUp
			#movemos la carpeta proyecto al directorio de vagrant y cambiamos nombre
			mv -f $proyecto*/*ent $dirVagrant/$proyecto.merxbp.loc
			#movemos los archivos sql
			mv -f $proyecto*/*.sql $dirVagrant/$proyecto.merxbp.loc/
			#Borrando el directorio creado por la extracción del .tar.gz
			rm -r */
			#Vamos al directorio donde se corre vagrant
			cd $dirVagrant
			#recargamos o cargamos vagrant segun sea el caso
			vagrant reload
			#verificamos su status
			responseVagrant="$(curl -I -s -L http://localhost:8080 | grep 'HTTP/1.1')"
			responseVagrantV=$( echo ${responseVagrant: -8:-4} )
			if [  $responseVagrantV == '404'  ]; then
				echo " "
				echo "===>Ups! Algo no esta funcionando en Vagrant..."
			else
				echo " "
				echo "Estamos actualizando la Base de Datos dentro de Vagrant..."
				#Actualizar la Base de Datos en Vagrant
				vagrant ssh -c "mysql -u root -proot -e 'drop database IF EXISTS ${proyecto}; create database ${proyecto}; show databases;'"
				vagrant ssh -c "mysql -u root -proot ${proyecto} < /vagrant/${proyecto}.merxbp.loc/*ent.sql"
				vagrant ssh -c "mysql -u root -proot ${proyecto} < /vagrant/${proyecto}.merxbp.loc/*ent_triggers.sql"

				echo " "
				vagrant ssh -c "mysql -u root -proot -e 'drop database IF EXISTS ${proyecto}_origin; create database ${proyecto}_origin; show databases;'"
				vagrant ssh -c "mysql -u root -proot ${proyecto}_origin < /vagrant/${proyecto}.merxbp.loc/*ent.sql"
				vagrant ssh -c "mysql -u root -proot ${proyecto}_origin < /vagrant/${proyecto}.merxbp.loc/*ent_triggers.sql"

				if [ $nameBranch != 'N' ]; then
					echo " "
					echo "Espera un poco más, estamos instalando cosas necesarias en tu instancia local como : composer y npm"
					#Instalando cosas necesarias para desarrollo local
					vagrant ssh -c "cd /vagrant/${proyecto}.merxbp.loc; composer install"
					vagrant ssh -c "cd /vagrant/${proyecto}.merxbp.loc; npm install"
				fi

				echo " "
				echo "Cambiando permisos en los archivos de la instancia"
				vagrant ssh -c "chmod 755 -R /vagrant/${proyecto}.merxbp.loc"

				if [ $nameBranch != 'N' ]; then
					#cambiamos a directorio de proyecto
					cd $dirVagrant/$proyecto.merxbp.loc

					#Configurando en instancia recien creada
					echo " "
					echo "Ahora configuramos tu repo Git..."

					touch .gitignore
					git init
					git add .gitignore
					git commit -m "Primer commit"
					echo "*" > .gitignore
					git add .gitignore
					git commit -m "Omitiendo archivos"

					git remote add merx "${gitMERX}"
					git remote add origin "git@github.com:${userGit}/custom_sugarcrm.git"

					echo " "
				  echo "Obteniendo cambios desde el repositorio remoto"
					git fetch merx
					git fetch origin
					git checkout -b ${nameBranch} merx/${nameBranch}
					# git config --add --global core.filemode false
					cd $dirVagrant
					echo " "
					echo "Reparando la instancia"
					vagrant ssh -c "cd /vagrant/${proyecto}.merxbp.loc; php repair.php"

					if [ $correrPruebas != 'N' ]; then
						echo " "
						echo "Ejecutando las pruebas PHP"
						vagrant ssh -c "cd /vagrant/${proyecto}.merxbp.loc; ../vendor/phpunit/phpunit/phpunit"
						echo " "
						echo "Ejecutando las pruebas JS"
						gruntJS=7.7
						$configFile = $dirVagrant/$proyecto.merxbp.loc/config.php
						version=$( cat "$configFile" | grep "'sugar_version' => '7.7*" )
						sugar_version=$( echo ${version: -9:-6} )
						sv=$( printf "%.1f" $sugar_version )
						r=$( echo "$sv <= $gruntJS" | bc )
						if [ $r -eq 1 ]; then
							echo ''
							echo 'Es la version 7.7 usaremos grunt'
							vagrant ssh -c "cd /vagrant/${proyecto}.merxbp.loc/tests; grunt karma:ci"
						else
							echo ''
							echo 'Es una version superior a la 7.7 usaremos gulp'
							vagrant ssh -c "cd /vagrant/${proyecto}.merxbp.loc/node_modules/gulp/bin/gulp.js karma --ci"
						fi
					fi
				fi
			fi
		else

			if [ $primeraVez == 'S' ]; then

				#movemos la carpeta proyecto al directorio de vagrant y cambiamos nombre
				mv -f $proyecto*/*ent $dirVagrant/$proyecto.merxbp.loc
				#movemos los archivos sql
				mv -f $proyecto*/*.sql $dirVagrant/$proyecto.merxbp.loc/
				#Borrando el directorio creado por la extracción del .tar.gz
				rm -r */
				#Vamos al directorio donde se corre vagrant
				cd $dirVagrant
				echo " "
				echo "Esto tardará un poco, descargando imagen Vagrant..."
				vagrant halt
				#Tener cuidado porque en ocasiones no corre completamente bien
				vagrant init mmarum/sugar7-php56
				vagrant up --provider virtualbox

				responseVagrant="$(curl -I -s -L http://localhost:8080 | grep 'HTTP/1.1')"
				responseVagrantV=$( echo ${responseVagrant: -8:-4} )
				if [  $responseVagrantV == '404'  ]; then
					echo " "
					echo "===>Ups! Algo no esta funcionando en Vagrant..."
				else
					echo " "
					echo "Estamos actualizando la Base de Datos dentro de Vagrant..."
					#Actualizar la Base de Datos en Vagrant
					vagrant ssh -c "mysql -u root -proot -e 'drop database IF EXISTS ${proyecto}; create database ${proyecto}; show databases;'"
					vagrant ssh -c "mysql -u root -proot ${proyecto} < /vagrant/${proyecto}.merxbp.loc/*ent.sql"
					vagrant ssh -c "mysql -u root -proot ${proyecto} < /vagrant/${proyecto}.merxbp.loc/*ent_triggers.sql"

					echo " "
					vagrant ssh -c "mysql -u root -proot -e 'drop database IF EXISTS ${proyecto}_origin; create database ${proyecto}_origin; show databases;'"
					vagrant ssh -c "mysql -u root -proot ${proyecto}_origin < /vagrant/${proyecto}.merxbp.loc/*ent.sql"
					vagrant ssh -c "mysql -u root -proot ${proyecto}_origin < /vagrant/${proyecto}.merxbp.loc/*ent_triggers.sql"

					if [ $nameBranch != 'N' ]; then
						echo " "
						echo "Espera un poco más, estamos instalando cosas necesarias en tu instancia local como : composer y npm"
						#Instalando cosas necesarias para desarrollo local
						vagrant ssh -c "cd /vagrant/${proyecto}.merxbp.loc; composer install"
						vagrant ssh -c "cd /vagrant/${proyecto}.merxbp.loc; npm install"
					fi

					echo " "
					echo "Cambiando permisos en los archivos de la instancia"
					vagrant ssh -c "chmod 755 -R /vagrant/${proyecto}.merxbp.loc"

					if [ $nameBranch != 'N' ]; then
						#cambiamos a directorio de proyecto
						cd $dirVagrant/$proyecto.merxbp.loc

						#Configurando en instancia recien creada
						echo " "
						echo "Ahora configuramos tu repo Git..."

						touch .gitignore
						git init
						git add .gitignore
						git commit -m "Primer commit"
						echo "*" > .gitignore
						git add .gitignore
						git commit -m "Omitiendo archivos"

						git remote add merx "${gitMERX}"
						git remote add origin "git@github.com:${userGit}/custom_sugarcrm.git"
						git fetch merx
						git fetch origin
						git checkout -b ${nameBranch} merx/${nameBranch}
						# git config --add --global core.filemode false

						cd $dirVagrant
						echo " "
						echo "Reparando la instancia"
						vagrant ssh -c "cd /vagrant/${proyecto}.merxbp.loc; php repair.php"

						if [ $correrPruebas != 'N' ]; then
							echo " "
							echo "Ejecutando las pruebas PHP"
							vagrant ssh -c "cd /vagrant/${proyecto}.merxbp.loc; ../vendor/phpunit/phpunit/phpunit"
							echo " "
							echo "Ejecutando las pruebas JS"

							gruntJS=7.7
							$configFile = $dirVagrant/$proyecto.merxbp.loc/config.php
							version=$( cat "$configFile" | grep "'sugar_version' => '7.7*" )
							sugar_version=$( echo ${version: -9:-6} )
							sv=$( printf "%.1f" $sugar_version )
							r=$( echo "$sv <= $gruntJS" | bc )
							if [ $r -eq 1 ]; then
								echo ''
								echo 'Es la version 7.7 usaremos grunt'
								vagrant ssh -c "cd /vagrant/${proyecto}.merxbp.loc/tests; grunt karma:ci"
							else
								echo ''
								echo 'Es una version superior a la 7.7 usaremos gulp'
								vagrant ssh -c "cd /vagrant/${proyecto}.merxbp.loc/node_modules/gulp/bin/gulp.js karma --ci"
							fi
						fi
					fi
				fi
			fi
			#Do while de directorio correcto
			#echo " "
			#echo "===>Seguramente te equivocaste..."
			#echo "===>¿Ruta completa donde se encuentra vagrant en tu equipo?"
			#read dirVagrant
		fi

		echo " "
		echo "Listo......."
		echo " "
		time=$(date +"%T")
		echo "Fin del proceso ${date} - ${time}"
	else
		echo " "
		echo "===>Debe estar solo el archivo más reciente de backup con terminación .tar.gz..."
		echo "===>Borre o mueva todos los archivos sobrantes en la carpeta backups..."
		echo "===>Y corra el script nuevamente por favor."
		exit
	fi
else
	echo " "
	echo "===>Lamentablemente no encontramos el proyecto: "
	echo "===>Proyecto: $proyecto"
	echo "===>Corra el script nuevamente e Ingrese nuevos datos por favor."
fi
exit
