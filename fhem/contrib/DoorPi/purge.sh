# ! /usr/bin/sh
action=$1

get_modify_time()
{
    stat $1 | grep -Po "Modify: \K[0-9- :]*"
}


if [ "$action" == "purge" ]; then
  reference=/var/run/doorpi.pid
  find records/ -type f ! -newer $reference -delete
elif [ "$action" == "clear" ]; then
  echo "clear"
  
else
  echo "so what"
fi 

