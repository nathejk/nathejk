NAME=nathejk
DOCKERHOST=172.17.0.1

boot:
	DOCKERHOST=$(DOCKERHOST) docker-compose --project $(NAME) up -d

install:
	apt-get update
	apt-get install apache2 dockerio docker-compose
	cp apache-virtualhost.conf /etc/apache2/sites-enabled/nathejk.conf

.PHONY: boot install
