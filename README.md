# README

## Overview

This repository contains a set of scripts to automate the end-to-end deployment of a self-hosted, mutual-TLS-enabled web application. 

The webserver is running on top of docker compose with NGINX. By default a placeholder site is loaded. To add different services add services to the docker compose file on the server and modify the nginx.conf file to setup path routing

It covers:

1. Preparing files with domain and email information
1. Generating SSL/TLS certificates (including a local CA for client-side mTLS).  
1. Packaging the server code into a deployable archive.  
1. Deploying that archive to a remote server (Ubuntu 22.x).

This can be expanded to cover docker applications behind nginx. 

## How to Install

Run the following scripts in order 

1. `prepare_server.sh`  
1. `generate-ssl-certificates.sh`  
1. `package-server.sh`  
1. `deploy-server.sh`  

## How to Test
1. Deploy Server
1. Install mobileprofile located at ./client/private_keys/client_certs
1. Go to server URL and test MTLS

## File Descriptions

- **prepare_server.sh**  
  - Must be run on macOS.  
  - Prompts for your real domain name and email address, then finds and replaces the `example.com` and `hello@example.com` placeholders throughout the project.  
  - Verifies you’re on the correct OS, installs any client-side prerequisites if needed, and prints the next steps.

- **generate-ssl-certificates.sh**  
  - Also macOS-only.  
  - Configures variables like `DOMAIN`, `EMAIL` and `P12_PASS`, then creates:  
    1. A root CA for client-side mTLS (private key + certificate).  
  	1. generates a mobileprofile.config file for mtls access to the web server
  	1. A server CSR and private key.  
    1. A PKCS#12 bundle for your server (used by many web servers).  
  - Outputs everything under ./client/private_keys/`).

- **package-server.sh**  
  - Packages the `server/` directory into  `selfhosted-mtls-webapp.tar.gz` archive.  
  - Disables macOS extended attributes (`COPYFILE_DISABLE=1`) and strips out metadata.  

- **deploy-server.sh**  
  - Copies the packaged archive to your remote host via `scp`, then SSHes in to:  
    1. Prompts for 
      * filename
      * ssh key
      * ssh username
      * ssh server IP or DNS name
    1. Unpack under `~/selfhosted-mtls-webapp`
    1. Sync the docker server files to `/srv/docker`
    1. Sync the generated `/etc/letsencrypt` certs.  
    1. Install Ubuntu 22.x prerequisites (`ubuntu22-installer.sh`).  
    1. Request Let’s Encrypt certs and start the server (`request_le_cert.sh`).  
  - Defaults to `../selfhosted-mtls-webapp.tar.gz`, `~/.ssh/app@example.com_ssh_key_id_ed25519`, `username@`, and `example.com`.

- **ubuntu22-installer.sh**
  - Runs once.
  - Updates system
  - Installs requirements
  - Sets up autoupdate

- **request_le_cert.sh**
  - Runs once a week
  - Stops webserver
  - Requests new signed certificates from Lets Encrypt
  - Restarts webserver with new certificates

- **docker_container_updater.sh**
  - Runs once a day
  - Stops web server
  - Pulls latest containers
  - Restarts

---