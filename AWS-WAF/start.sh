#!/bin/bash
###########################################################################
##       ffff55555                                                       ##
##     ffffffff555555                                                    ##
##   fff      f5    55         Deployment Script Version 0.0.1           ##
##  ff    fffff     555                                                  ##
##  ff    fffff f555555                                                  ##
## fff       f  f5555555             Written By: EIS Consulting          ##
## f        ff  f5555555                                                 ##
## fff   ffff       f555             Date Created: 12/02/2015            ##
## fff    fff5555    555             Last Updated: 06/03/2016            ##
##  ff    fff 55555  55                                                  ##
##   f    fff  555   5       This script will start the pre-configured   ##
##   f    fff       55       WAF configuration.                          ##
##    ffffffff5555555                                                    ##
##       fffffff55                                                       ##
###########################################################################
###########################################################################
##                              Change Log                               ##
###########################################################################
## Version #     Name       #                    NOTES                   ##
###########################################################################
## 11/23/15#  Thomas Stanley#    Created base functionality              ##
## 06/02/16#  Thomas Stanley#    FInished base functionality             ##
## 06/03/16#  Thomas Stanley#    Adding admin password change            ##
###########################################################################

### Parameter Legend  ###
## devicearr=0 #ismaster true or false
## devicearr=1 #hostname of this device
## devicearr=2 #IP address of this device
## devicearr=3 #login password for the WAF
## devicearr=4 #BYOL License key
## devicearr=5 #the name of the application
## devicearr=6 #master hostname
## devicearr=7 #master address
## vipportarr=0 #port numbers of the BIG-IP VIP semicolon delimited (80;443;8080)
## protocolarr=0 #protocol for the VIP like http or https semicolon delimited
## hostarr=0 #ip address of the application servers, or fqdn of applicaiton
## hostarr=1 #region or location of the URL (westus, eastus)
## appportarr=0 #the port of the application (80;443;8080)
## asmarr=0 # linux or windows
## asmarr=1 #blocking level, high medium low
## asmarr=2 #fqdn for the application
## asmarr=3 #secure string of SSL certificate file path
## asmarr=4 #secure string of SSL key file path
## asmarr=5 #secure string of SSL chain file path

## Preset Variables
OS_USER_DATA_RETRIES=20
OS_USER_DATA_RETRY_INTERVAL=10
OS_USER_DATA_RETRY_MAX_TIME=300


## Helper Functions
#### check if MCP is running
function wait_mcp_running() {
  failed=0
  STATUS_CHECK_RETRIES=6
  STATUS_CHECK_INTERVAL=10

  while true; do
    # this will log an error when mcpd is not up
    tmsh -a show sys mcp-state field-fmt | grep -q running 

    if [[ $? == 0 ]]; then
    echo "Successfully ran tmsh command..."
    return 0
    fi

    failed=$(($failed + 1))

    if [[ $failed -ge $STATUS_CHECK_RETRIES ]]; then
      echo "Failed to connect to mcpd after $failed attempts, quitting..."      
      return 1
    fi

    echo "Could not connect to mcpd (attempt $failed/$STATUS_CHECK_RETRIES), retrying in $STATUS_CHECK_INTERVAL seconds..."
    sleep $STATUS_CHECK_INTERVAL
  done
}

## Build the arrays based on the semicolon delimited command line argument passed from json template, and save them to a file.
IFS=';' read -ra devicearr <<< "$1"
echo "$1" >> /config/inbound_params.txt
IFS=';' read -ra vipportarr <<< "$2"    
echo "$2" >> /config/inbound_params.txt
IFS=';' read -ra protocolarr <<< "$3"   
echo "$3" >> /config/inbound_params.txt 
IFS=';' read -ra hostarr <<< "$4"    
echo "$4" >> /config/inbound_params.txt
IFS=';' read -ra appportarr <<< "$5" 
echo "$5" >> /config/inbound_params.txt   
IFS=';' read -ra asmarr <<< "$6"
# string to lower asmarr[0] and asmarr[1]
string1="${asmarr[0],,}"
string2="${asmarr[1],,}"
asmarr[0]="$string1"
asmarr[1]="$string2"
echo "$6" >> /config/inbound_params.txt

## find our internal IP address and populate devicearr2
ipaddr=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/')
if [ "${devicearr[2]}" = "" ]
then
	devicearr[2]="$ipaddr"
fi

## Get certificate file if it was supplied.
if [ "${asmarr[3]}" != "" ]
then
	certpath="${asmarr[3]}"
	IFS='/' read -a certpatharr <<< "$certpath"
	certlength=${#certpatharr[@]}
	certlastposition=$((certlength - 1))
	certfilename=${certpatharr[${certlastposition}]}
	#curl -kO ${asmarr[3]}	
	curl -k -s -f --retry $OS_USER_DATA_RETRIES --retry-delay $OS_USER_DATA_RETRY_INTERVAL --retry-max-time $OS_USER_DATA_RETRY_MAX_TIME -o "/config/ssl/$certfilename" "$certpath"
	certpath="file::/config/ssl/$certfilename"
	#mv /config/"$certfilename" /config/ssl/"$certfilename"
fi

## Get key file if it was supplied.
if [ "${asmarr[4]}" != "" ]
then
	keypath=${asmarr[4]}
	IFS='/' read -ra keypatharr <<< "$keypath"
	keylength=${#keypatharr[@]}
	keylastposition=$((keylength - 1))
	keyfilename=${keypatharr[${keylastposition}]}
	#curl -kO ${asmarr[4]}
	curl -k -s -f --retry $OS_USER_DATA_RETRIES --retry-delay $OS_USER_DATA_RETRY_INTERVAL --retry-max-time $OS_USER_DATA_RETRY_MAX_TIME -o "/config/ssl/$keyfilename" "$keypath"
	keypath="file::/config/ssl/$keyfilename"
	#mv /config/"$keyfilename" /config/ssl/"$keyfilename"
fi

## Get chain file if it was supplied.
if [ "${asmarr[5]}" != "" ]
then
	chainpath=${asmarr[5]}
	IFS='/' read -ra chainpatharr <<< "$chainpath"
	chainlength=${#chainpatharr[@]}
	chainlastposition=$((chainlength - 1))
	chainfilename=${chainpatharr[${chainlastposition}]}
	#curl -kO ${asmarr[5]}
	curl -k -s -f --retry $OS_USER_DATA_RETRIES --retry-delay $OS_USER_DATA_RETRY_INTERVAL --retry-max-time $OS_USER_DATA_RETRY_MAX_TIME -o "/config/ssl/$chainfilename" "$chainpath"
	chainpath="file::/config/ssl/$chainfilename"
	#mv /config/"$chainfilename" /config/ssl/"$chainfilename"
fi


## Construct the blackbox.conf file using the arrays.
row1='"1":["'${vipportarr[0]}'","'${protocolarr[0]}'",["'${hostarr[0]}':'${appportarr[0]}'"],"","","","","","'${asmarr[0]}'","'${asmarr[1]}'","yes","yes","yes","wanlan","'${asmarr[2]}'","yes","","","","",""]'
row2='"2":["'${vipportarr[1]}'","'${protocolarr[1]}'",["'${hostarr[0]}':'${appportarr[1]}'"],"","","","","","'${asmarr[0]}'","'${asmarr[1]}'","yes","yes","yes","wanlan","'${asmarr[2]}'","yes","","","'${certpath}'","'${keypath}'","'${chainpath}'"]'

deployment1='deployment_'${devicearr[5]}'.'${hostarr[1]}'.cloudapp.azure.com":{"traffic-group":"none","strict-updates":"disabled","variables":{},"tables":{"configuration__destination":{"column-names":["port","mode","backendmembers","monitoruser","monitorpass","monitoruri","monitorexpect","asmtemplate","asmapptype","asmlevel","l7ddos","ipintel","caching","tcpoptmode","fqdns","oneconnect","sslpkcs12","sslpassphrase","sslcert","sslkey","sslchain"],"rows":{'$row1','$row2'}}}}'

jsonfile='{"loadbalance":{"is_master":"'${devicearr[0]}'","master_hostname":"'${devicearr[6]}'","master_address":"'${devicearr[7]}'","master_password":"'${devicearr[3]}'","device_hostname":"'${devicearr[1]}'","device_address":"'${devicearr[2]}'","device_password":"'${devicearr[3]}'"},"logging":{"saskey":"tAjn8Xuzelj9ps4HzRsHXqXznAIiHPFIzlSC08De2Zk=","saskeyname":"sharing-is-caring","eventhub":"event-horizon","eventhub_namespace":"event-horizon-ns","logginglevel":"Alert","loggingtemplate":"CEF","applianceid":"8A3ED335-F734-449F-A8FB-335B48FE3B50"},"bigip":{"application_name":"Azure Security F5 WAF","ntp_servers":"1.pool.ntp.org 2.pool.ntp.org","ssh_key_inject":"false","change_passwords":"false","license":{"basekey":"'${devicearr[4]}'"},"modules":{"auto_provision":"true","ltm":"nominal","afm":"none","asm":"nominal"},"redundancy":{"provision":"false"},"network":{"provision":"false"},"iappconfig":{"f5.rome_waf_rc":{"template_location":"http://cdn-prod-ore-f5.s3-website-us-west-2.amazonaws.com/product/blackbox/staging/azure/f5.rome_waf_rc.tmpl","deployments":{"'$deployment1'}}}}}'

echo $jsonfile > /config/blackbox.conf

## Move the files and run them.
# mv ./azuresecurity.sh /config/azuresecurity.sh
# chmod +w /config/startup
(wait_mcp_running)
if [[ $? == 0 ]]; then
	tmsh modify auth user "admin" password "${devicearr[3]}"
else
	echo "Failed to change the admin password, the rest of the setup will fail. so exiting..."
	exit
fi
echo "bash -x /config/azuresecurity.sh &> /config/azuresecurity2.log" >> /config/startup
bash -x /config/azuresecurity.sh &> /config/azuresecurity.log
