NAME=nathejk

space :=
space +=

configlist := $(strip docker-compose.yml $(shell ls ../*/docker-compose-dev.yml 2>/dev/null))
config := -f $(subst $(space),$(space)-f$(space),$(configlist))
project := --project $(NAME)
dockercompose := docker-compose $(project) $(config)

boot: db
	$(dockercompose) up -d --remove-orphans

stop:
	$(dockercompose) down

install:
	apt-get update
	apt-get install apache2 dockerio docker-compose
	cp apache-virtualhost.conf /etc/apache2/sites-enabled/nathejk.conf

grantsql:
	@echo "CREATE DATABASE IF NOT EXISTS nathejk2016; GRANT ALL PRIVILEGES ON nathejk2016.* TO nathejk@'%' IDENTIFIED BY 'kodeord';"
	@echo "CREATE DATABASE IF NOT EXISTS sms; GRANT ALL PRIVILEGES ON sms.* TO nathejk@'%' IDENTIFIED BY 'kodeord';"
	@echo "CREATE DATABASE IF NOT EXISTS mail; GRANT ALL PRIVILEGES ON mail.* TO nathejk@'%' IDENTIFIED BY 'kodeord';"

sql:
	$(dockercompose) config | grep "@mysql/"

db:
	$(dockercompose) up -d mysql
	$(dockercompose) exec mysql mysqladmin -pib ping --wait=30
	$(dockercompose) exec -T mysql bash -c "echo \"$(shell make grantsql)\" | mysql -pib"



.PHONY: boot install
