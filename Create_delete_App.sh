#!/bin/bash

#This is for pretty printing
bold=$(tput bold)
underline=$(tput smul)
italic=$(tput sitm)
info=$(tput setaf 2)
error=$(tput setaf 160)
warn=$(tput setaf 214)
reset=$(tput sgr0)

banner()
{
  echo "+---------------------------------------------------------------------------------+"
  printf "| %-80s |\n" "`date`"
  echo "|                                                                                  |"
  printf "|`tput bold` %-80s `tput sgr0`|\n" "$@"
  echo "+---------------------------------------------------------------------------------+"
}

##
#This function is responsible for the Finding if a String is present in the list.
##
function exists_in_list() {
    LIST=$1
    DELIMITER=$2
    VALUE=$3
    LIST_WHITESPACES=`echo $LIST | tr "$DELIMITER" " "`
    for x in $LIST_WHITESPACES; do
        if [ "$x" = "$VALUE" ]; then
            return 0
        fi
    done
    return 1
}

#Clear the console 
clear

banner "ADB2C application to create or delete application with Tenants"
sleep 1

PS3="$(tput bold)Select the directory: $(tput sgr0)"
select opt in <tenanat 1>, <tenant 2> quit; do # this needs to be replaced. Reffer blog

    is_logged_in="$(az account show -o jsonc --query id  -o tsv)"
    echo $is_logged_in
    if [ -z "$is_logged_in" ]
        then 
            echo "${warn}Going to Perform the Azure Login against: $opt${reset}"
            # Ask for which directory to login
            login_res="$( az login --tenant $opt --allow-no-subscriptions )"
        else
            # Creation especially providing oauth permissions are breaking without a login. Hence forcing login.
            echo "${warn}Seems you are allready logged in , However Creation will throw an error if you are not logged in recently. Forcing Login! ${reset}"
            login_res="$( az login --tenant $opt --allow-no-subscriptions )"
        fi
    
    # echo "************"  #enable if you want to see sensitive content after login
    # echo $login_res
    # echo "************"

    if [ -z "$login_res" ]
        then 
            echo "${error}Login Failed to the Azure Login Tenant with Requried Access ${reset}" 
            exit 1
        else
            echo "Login Success Lets try to pull the App details!"
            echo "Listing all existing Apps ->"
            all_apps="$(az ad app list --query '[].displayName' -o tsv)"
            echo $all_apps
            echo "************* App Listing ends Here ***********"

            echo "$(tput bold) What do you intend to do today? ${reset}"
            select action in Create delete quit; do
               
                    echo "You picked $action"
                    case $action in
                        Create )
                            echo "${info}You are in create Menu. Happy Application Creation !" 
                            echo "Enter the Application Name to Create: "  
                            read application_name  
                            if exists_in_list "$all_apps" "," "$application_name"; then
                                echo "${info} Application  is in the list , Choose another name to move forward! ${reset}"
                            else
                                echo "${error} Application does not Exist, we can move forward to create one, Moving Forward to Creation ${reset}"
                                sleep 1
                                echo "${warn} enter the redirect URI for the application: press enter to choose https://jwt.ms as redirect URI ${reset}"
                                read redirect_uri
                                regex='(https?|ftp|file)://[-[:alnum:]\+&@#/%?=~_|!:,.;]*[-[:alnum:]\+&@#/%=~_|]'
                                if [[ $redirect_uri =~ $regex ]]
                                then 
                                    echo "Link valid"
                                else
                                    echo "Link not valid, Falling back to default one https://jwt.ms"
                                    redirect_uri='https://jwt.ms'
                                fi

                                echo "${info} Fetching MS Graph ID ${reset}"
                                az ad sp list --query "[?appDisplayName=='Microsoft Graph'].appId | [0]" --all
                                graphId="$(az ad sp list --query "[?appDisplayName=='Microsoft Graph'].appId | [0]" --all -o tsv)"
                                sleep 1

                                #These Scope ID's are needed for the OAUTH Permissions.
                                openid="$(az ad sp show --id $graphId --query "oauth2PermissionScopes[?value=='openid'].id | [0]" )"
                                profile="$(az ad sp show --id $graphId --query "oauth2PermissionScopes[?value=='profile'].id | [0]" )"
                                offline_access="$(az ad sp show --id $graphId --query "oauth2PermissionScopes[?value=='offline_access'].id | [0]" )"

                                resources=$(cat <<EOF
                                            [{ "resourceAppId": "${graphId}", "resourceAccess": [{"id": $openid,"type": "Scope"},{"id": $offline_access,"type": "Scope"}]}] )

                                echo "${info} Printing Permissions for OAUTH $resources ${reset}"
                                sleep 1

                                echo "${info} Creating Application --> and the Application ID is :${reset}" 
                                created_application_id="$(az ad app create --display-name $application_name --enable-access-token-issuance true --sign-in-audience AzureADandPersonalMicrosoftAccount --web-redirect-uris $redirect_uri --required-resource-accesses "$resources" --query appId -o tsv)"
                                echo $created_application_id
                                sleep 1

                                echo "${warn} Creating a Service Principal so that Application has sufficient access ${reset}"
                                az ad sp create --id "${created_application_id}"
                                sleep 1

                                echo "${Info} Creating the client Credentials for $created_application_id ${reset}"
                                final_response="$(az ad app credential reset --id $created_application_id --append --years 2)"
                                sleep 5

                                echo "${warn} Providing OAUTH Scopes Admin Consent so it can generate that token! ${reset}" 
                                az ad app permission admin-consent --id "${created_application_id}"
                                sleep 1
                                
                                echo ""
                                echo "!!!!!!!!!!!!Please Read!!!!!!!!!!!!!!!"
                                echo "${warn} if the above steps fails, This is because some times the Grahql Call timesout behind, Please manually run below command and it will work!. IF no failure ignore this warning. ${reset}"
                                echo "${error} az ad app permission admin-consent --id ${created_application_id} ${reset}"
                                 echo "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

                                echo "***************"
                                echo $final_response
                                echo "----------------"
                                echo "***** Make sure to save the response above, as you wont be able to reterive secret later ***********"

                            fi
                            break
                            ;;

                        delete )

                            echo "${warn}You are in delete Menu. Proceed with Caution !!!!"
                            echo "Enter the Application Name to Delete: "  
                            read application_name  
                            if exists_in_list "$all_apps" "," "$application_name"; then
                                echo "${warn} Application  is in the list , Moving forward with Deletion! ${reset}"
                                echo "${info}Going to Fetch the Application ID for $application_name ${reset}"
                                application_Id="$(az ad app list --display-name $application_name --query '[].appId' -o tsv)"
                                read -p "Are you sure you want to continue deleting $application_Id? <y/N> " prompt
                                if [[ $prompt == "y" || $prompt == "Y" || $prompt == "yes" || $prompt == "Yes" ]]
                                then
                                   del_response="$(az ad app delete --id $application_Id)"
                                else
                                   break
                                fi

                            else
                                echo "${error} Application does not Exist, we cannot move forward with Deletion. $(reset)"
                            fi 
                            break
                            ;;

                         quit )
                            break
                    esac
            done
    fi

#All ends here
banner "Execution Complete"
exit 1
done
