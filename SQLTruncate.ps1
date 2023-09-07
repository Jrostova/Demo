clear
# Check if dbatools is installed
if (-not (Get-Module -ListAvailable -Name dbatools)) {
    # If not installed, install it
    Install-Module -Name dbatools 
} else {
    # If installed, check for updates
    $CurrentVersion = (Get-Module -ListAvailable -Name dbatools).Version
    $LatestVersion = (Find-Module -Name dbatools).Version

    if ($LatestVersion -gt $CurrentVersion) {
        # If updates are available, update it
        Update-Module -Name dbatools -Force
    }
}

# Set defaults just for this session
Set-DbatoolsConfig -FullName sql.connection.trustcert -Value $true
Set-DbatoolsConfig -FullName sql.connection.encrypt -Value $false
param(
    [string]$sqlInstance = 'servername',
    [string]$database = 'DB_name',
    [string[]]$tables = @('ProviderInvoices'), # Replace with your actual table names
    [PSCredential]$sqlCredential = $null
)

# Connect to the SQL Server instance
$server = if ($sqlCredential) {
    Connect-DbaInstance -SqlInstance $sqlInstance -Database $database -SqlCredential $sqlCredential -DisableException
} else {
    Connect-DbaInstance -SqlInstance $sqlInstance -Database $database -DisableException
}

# Truncate the specified tables
$tables | ForEach-Object {
    $currentTable = $_

    # Get the foreign keys that reference the table
    $foreignKeys = Get-DbaDbForeignKey -SqlInstance $server -Database $database | Where-Object { $_.ReferencedTable -eq $currentTable }

    # Generate a DROP CONSTRAINT script for each foreign key
    $dropScripts = $foreignKeys | ForEach-Object { "ALTER TABLE $($_.Parent) DROP CONSTRAINT $($_.Name)" }

    # Execute the DROP CONSTRAINT scripts
    $dropScripts | ForEach-Object { Invoke-DbaQuery -SqlInstance $server -Database $database -Query $_ }

    # Truncate the table
    $server.databases[$database].Tables[$currentTable].TruncateData()

    # Generate a ADD CONSTRAINT script for each foreign key
    $addScripts = $foreignKeys | ForEach-Object { "ALTER TABLE $($_.Parent) ADD CONSTRAINT $($_.Name) FOREIGN KEY ($($_.Columns -join ', ')) REFERENCES $($_.ReferencedTable) ($($_.ReferencedColumns))" }

    # Execute the ADD CONSTRAINT scripts
    $addScripts | ForEach-Object { Invoke-DbaQuery -SqlInstance $server -Database $database -Query $_ }
}
