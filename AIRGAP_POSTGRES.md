1. Create a Helm deployment of postgresql 18 which only pulls from one image registry.
2. The HA load balancing needs to be built out here because we can't pull from any other repos but this one for Postgres.
3. Create a Kubernetes Cronjob that backups the database every hour.
4. Create an automated script for recovering the database from the backup that can be invoked through Kubernetes as well.
5. Using kubectl, test the deployment and check for issues.