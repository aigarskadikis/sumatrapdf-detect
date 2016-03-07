#!/bin/sh

#this code is tested un fresh 2015-11-21-raspbian-jessie-lite Raspberry Pi image
#by default this script should be located in two subdirecotries under the home

#sudo apt-get update -y && sudo apt-get upgrade -y
#sudo apt-get install git -y
#mkdir -p /home/pi/detect && cd /home/pi/detect
#git clone https://github.com/catonrug/sumatrapdf-detect.git && cd sumatrapdf-detect && chmod +x check.sh && ./check.sh

#check if script is located in /home direcotry
pwd | grep "^/home/" > /dev/null
if [ $? -ne 0 ]; then
  echo script must be located in /home direcotry
  return
fi

#it is highly recommended to place this directory in another directory
deep=$(pwd | sed "s/\//\n/g" | grep -v "^$" | wc -l)
if [ $deep -lt 4 ]; then
  echo please place this script in deeper directory
  return
fi

#set application name based on directory name
#this will be used for future temp directory, database name, google upload config, archiving
appname=$(pwd | sed "s/^.*\///g")

#set temp directory in variable based on application name
tmp=$(echo ../tmp/$appname)

#create temp directory
if [ ! -d "$tmp" ]; then
  mkdir -p "$tmp"
fi

#check if database directory has prepared 
if [ ! -d "../db" ]; then
  mkdir -p "../db"
fi

#set database variable
db=$(echo ../db/$appname.db)

#if database file do not exist then create one
if [ ! -f "$db" ]; then
  touch "$db"
fi

#check if google drive config directory has been made
#if the config file exists then use it to upload file in google drive
#if no config file is in the directory there no upload will happen
if [ ! -d "../gd" ]; then
  mkdir -p "../gd"
fi

if [ -f ~/uploader_credentials.txt ]; then
sed "s/folder = test/folder = `echo $appname`/" ../uploader.cfg > ../gd/$appname.cfg
else
echo google upload will not be used cause ~/uploader_credentials.txt do not exist
fi

#application name
name=$(echo "SumatraPDF")

#this is site javascript which includes information about latest version
url=$(echo "http://www.sumatrapdfreader.org/sumatra.js")

#set download base
dlbase=$(echo "https://kjkpub.s3.amazonaws.com/sumatrapdf/rel/SumatraPDF-")

#change log location
changes=$(echo "http://www.sumatrapdfreader.org/news.html")

#lets tauch a little bit javascript file to see if it is there 
wget -S --spider -o $tmp/output.log "$url"

#if file request retrieve http code 200 this means OK
grep -A99 "^Resolving" $tmp/output.log | grep "HTTP.*200 OK"
if [ $? -eq 0 ]; then

#look for latest version number
version=$(wget -qO- $url | grep "var gSumVer " | sed "s/\d034/\n/g" | grep "[0-9\.]\+")
echo $version | grep -v "[A-Za-z]" | grep "[0-9\.]"
if [ $? -eq 0 ]; then

#check if this version information is in database
grep "$version" $db
if [ $? -ne 0 ]
then
echo new version detected!

#get change log
wget -qO- "$changes" | grep -A99 version_history | grep -m2 -B99 "<b id=" | grep -v "<h2 \|<b id=" | sed -e "s/<[^>]*>//g" | grep "\w" | sed "s/^[ \t]*//g" | sed -e "/release:/! s/^/- /" > $tmp/change.log

#check if even something has been created
if [ -f $tmp/change.log ]; then

#calculate how many lines log file contains
lines=$(cat $tmp/change.log | wc -l)
if [ $lines -gt 0 ]; then
echo change log found:
echo

cat $tmp/change.log

#we have 32-bit and 64-bit version installers an so as portable versions
filetypes=$(cat <<EOF
-install.exe
-64-install.exe
.zip
-64.zip
extra line
EOF
)

printf %s "$filetypes" | while IFS= read -r type
do {

#define installer url
url=$(echo "$dlbase$version$type")

#calculate exact filename of link
filename=$(echo $url | sed "s/^.*\///g")

echo Downloading $filename
wget $url -O $tmp/$filename -q
echo

echo creating sha1 checksum of file..
sha1=$(sha1sum $tmp/$filename | sed "s/\s.*//g")
echo

echo creating md5 checksum of file..
md5=$(md5sum $tmp/$filename | sed "s/\s.*//g")
echo

echo "$version">> $db
echo "$filename">> $db
echo "$md5">> $db
echo "$sha1">> $db
echo >> $db


#if google drive config exists then upload and delete file:
if [ -f "../gd/$appname.cfg" ]
then
echo Uploading $filename to Google Drive..
echo Make sure you have created \"$appname\" directory inside it!
../uploader.py "../gd/$appname.cfg" "$tmp/$filename"
echo
fi

case "$type" in
-64-install.exe)
title=$(echo "(64-bit)")
;;
-64.zip)
title=$(echo "(64-bit) portable")
;;
-install.exe)
title=$(echo "(32-bit)")
;;
.zip)
title=$(echo "(32-bit) portable")
;;
esac


#lets send emails to all people in "posting" file
emails=$(cat ../posting | sed '$aend of file')
printf %s "$emails" | while IFS= read -r onemail
do {
python ../send-email.py "$onemail" "$name $version $title" "$url 
$md5
$sha1

`cat $tmp/change.log`"
} done
echo

} done

else
#changes.log file has created but changes is mission
echo changes.log file has created but changes is mission
emails=$(cat ../maintenance | sed '$aend of file')
printf %s "$emails" | while IFS= read -r onemail
do {
python ../send-email.py "$onemail" "$name" "changes.log file has created but changes is mission: 
$version 
$changes "
} done
fi

else
#changes.log has not been created
echo changes.log has not been created
emails=$(cat ../maintenance | sed '$aend of file')
printf %s "$emails" | while IFS= read -r onemail
do {
python ../send-email.py "$onemail" "$name" "changes.log has not been created: 
$version 
$changes "
} done
fi

else
#version is already in database
echo version is already in database
fi

else
#version information do not match version pattern
echo version information do not match version pattern
emails=$(cat ../maintenance | sed '$aend of file')
printf %s "$emails" | while IFS= read -r onemail
do {
python ../send-email.py "$onemail" "$name" "version information do not match version pattern:
$url 
$version"
} done
echo 
echo
fi

else
#if http statis code is not 200 ok
emails=$(cat ../maintenance | sed '$aend of file')
printf %s "$emails" | while IFS= read -r onemail
do {
python ../send-email.py "$onemail" "$name" "the following link do not retrieve good http status code: 
$url"
} done
echo 
echo
fi

#clean and remove whole temp direcotry
rm $tmp -rf > /dev/null
