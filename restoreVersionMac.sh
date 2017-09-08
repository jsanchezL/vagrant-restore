#!/bin/sh

gitMERX="git@github.com:MerxBusinessPerformance/custom_sugarcrm.git"
now=$(date +"%Y-%m-%d")
time=$(date +"%T")

clear

#El orden de los parametros son:
primeraVez=$1
proyecto=$2
sugar_vagrant_dir=$3
nameBranch=$4
user_github=$5
correrPruebas=$6

esOndemand=$7
urlOnSite=$8
db_host_name=$9
db_user_name=${10}
db_password=${11}
db_name=${12}
host_elastic=${13}

instance_dir=$sugar_vagrant_dir/$proyecto.merxbp.loc
lastest="${PWD}/proyectos/$proyecto/backups/lastest"

echo " "
echo "Restaurando Instancia ${proyecto} en Local..."
echo " "
echo "Inicio del proceso ${now} - ${time}......."

echo " "
echo "Eliminando instancia obsoleta... "
rm -rf $instance_dir

echo " "
echo "Extrayendo restore files ... "
cd $lastest
tar -zxvf ${proyecto}.sugarondemand.com*.tar.gz
cd ${proyecto}.sugarondemand.com.*
mv sugar*ent $instance_dir
mv sugar*ent.sql $instance_dir

echo " "
echo "Modificando archivo config.php ..."
cd $instance_dir
vagrant ssh -c 'sed -i "s/${db_host_name}/localhost/g" /vagrant/${proyecto}.merxbp.loc/config.php'
vagrant ssh -c 'sed -i "s/${db_user_name}/root/g" /vagrant/${proyecto}.merxbp.loc/config.php'
vagrant ssh -c 'sed -i "s/${db_password}/root/g" /vagrant/${proyecto}.merxbp.loc/config.php'
vagrant ssh -c 'sed -i "s/${db_name}/${proyecto}/g" /vagrant/${proyecto}.merxbp.loc/config.php'
if [ $esOndemand == 'S' ]; then
  vagrant ssh -c 'sed -i "s/${proyecto}.sugarondemand.com/$proyecto.merxbp.loc/g" /vagrant/${proyecto}.merxbp.loc/config.php'
else
  vagrant ssh -c 'sed -i "s/${urlOnSite}/${proyecto}.merxbp.loc/g" /vagrant/${proyecto}.merxbp.loc/config.php'
fi
vagrant ssh -c 'sed -i "s/${host_elastic}/localhost/g" /vagrant/${proyecto}.merxbp.loc/config.php'
vagrant ssh -c 'rm -rf /vagrant/${proyecto}.merxbp.loc/cache/*'
vagrant ssh -c 'chmod 777 -R /vagrant/${proyecto}.merxbp.loc'

echo " "
echo "Modificando archivos .htaccess ..."
vagrant ssh -c 'sed -i "s/RewriteBase \//RewriteBase \/sugar\/${proyecto}.merxbp.loc\//g" /vagrant/${proyecto}.merxbp.loc/.htaccess'
echo " "
echo "Restaurando base de datos ..."
vagrant ssh -c "mysql -u root -proot -e 'drop database IF EXISTS ${proyecto}; create database ${proyecto}; show databases;'"
vagrant ssh -c "mysql -u root -proot ${proyecto} < /vagrant/${proyecto}.merxbp.loc/*ent.sql"
vagrant ssh -c "mysql -u root -proot ${proyecto} < /vagrant/${proyecto}.merxbp.loc/*ent_triggers.sql"

echo " "
vagrant ssh -c "mysql -u root -proot -e 'drop database IF EXISTS ${proyecto}_origin; create database ${proyecto}_origin; show databases;'"
vagrant ssh -c "mysql -u root -proot ${proyecto}_origin < /vagrant/${proyecto}.merxbp.loc/*ent.sql"
vagrant ssh -c "mysql -u root -proot ${proyecto}_origin < /vagrant/${proyecto}.merxbp.loc/*ent_triggers.sql"

if [ $nameBranch != 'N' ]; then
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

  echo " "
  echo "Instalando dependencias  ..."
  vagrant ssh -c "cd /vagrant/${proyecto}.merxbp.loc; composer install"
  vagrant ssh -c "cd /vagrant/${proyecto}.merxbp.loc; npm install"

  echo "Reparando la instancia"
  vagrant ssh -c "cd /vagrant/${proyecto}.merxbp.loc; php repair.php"

  if [ $correrPruebas != 'N' ]; then
    echo " "
    echo "Ejecutando las pruebas PHP"
    vagrant ssh -c "cd /vagrant/${proyecto}.merxbp.loc/tests; ../vendor/phpunit/phpunit/phpunit"
    echo " "
    echo "Ejecutando las pruebas JS"
    #Checar como obtener la versión de sugar en Mac ver script linux
    vagrant ssh -c "cd /vagrant/${proyecto}.merxbp.loc/tests; grunt karma:ci"
    #Version 7.8 o superior
    #vagrant ssh -c "cd /vagrant/${proyecto}.merxbp.loc/node_modules/gulp/bin/gulp.js karma --ci"
  fi
fi

echo " "
echo "Listo......."
echo " "
time=$(date +"%T")
echo "Fin del proceso ${date} - ${time}"
