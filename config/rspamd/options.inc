# rspamd local.d/options.inc
# A scan may wait up to 60 s for clamd during a signature reload
# (antivirus.conf); the default task_timeout of 8 s would end the task first
# and pass the mail unscanned.  Postfix waits 300 s for the milter
# (milter_content_timeout).
task_timeout = 90s;
