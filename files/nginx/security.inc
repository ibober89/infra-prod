# Security include for blocking and logging exploit probes across all server blocks
location ~* ^/(\.env|phpunit|cgi-bin|\.git|\.aws|\.docker|wp-admin|wp-content|setup\.php|phpinfo\.php|eval-stdin) {
    access_log /var/log/nginx/suspicious.log main;
    return 404;
}
