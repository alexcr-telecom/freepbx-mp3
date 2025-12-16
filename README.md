# freepbx-mp3
script for convert wav to mp3 and update mysql asteriskcdrdb - with new file name 

**Post Call Recording Hook** (FreePBX → Settings → Advanced Settings → Post Call Recording Script):

   /usr/local/bin/convert_recordings.sh ^{MIXMON_DIR}^{YEAR}/^{MONTH}/^{DAY}/^{CALLFILENAME}.^{MIXMON_FORMAT}


# Clear old records 
cp recording_maintenance.sh /usr/local/bin/   

chmod +x /usr/local/bin/recording_maintenance.sh

# Crontab
0 1 * * * /usr/local/bin/recording_maintenance.sh >> /var/log/asterisk/recording_maintenance.log 2>&1
