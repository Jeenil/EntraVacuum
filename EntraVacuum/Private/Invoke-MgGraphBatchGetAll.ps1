function Invoke-MgGraphBatchGetAll {
    <#
    .SYNOPSIS
        Executes multiple Graph GET requests in a single batch call and handles pagination.

    .DESCRIPTION
        Uses the $batch endpoint to send up to 20 GET requests at once, then follows
        @odata.nextLink for any paged responses. Returns a hashtable keyed by request ID.

    .PARAMETER Requests
        Array of request objects, each with 'id', 'method', and 'url' properties.

    .EXAMPLE
        $requests = @(
            @{ id = '1'; method = 'GET'; url = '/users?$select=id,displayName' }
            @{ id = '2'; method = 'GET'; url = '/groups?$select=id,displayName' }
        )
        $results = Invoke-MgGraphBatchGetAll -Requests $requests
        $users = $results['1']
    #>
    param (
        [Parameter(Mandatory)]
        [array] $Requests
    )

    $results = @{}
    $batchSize = 20

    for ($i = 0; $i -lt $Requests.Count; $i += $batchSize) {
        $chunk = $Requests[$i..([Math]::Min($i + $batchSize - 1, $Requests.Count - 1))]

        $batchBody = @{ requests = $chunk } | ConvertTo-Json -Depth 5
        $batchResponse = Invoke-MgGraphRequest -Method POST `
            -Uri 'https://graph.microsoft.com/v1.0/$batch' `
            -Body $batchBody

        foreach ($response in $batchResponse.responses) {
            $allItems = [System.Collections.Generic.List[object]]::new()

            if ($response.body.value) {
                $allItems.AddRange($response.body.value)
            }

            # Follow nextLink for paged results
            $nextLink = $response.body.'@odata.nextLink'
            while ($nextLink) {
                $page = Invoke-MgGraphRequest -Method GET -Uri $nextLink
                if ($page.value) { $allItems.AddRange($page.value) }
                $nextLink = $page.'@odata.nextLink'
            }

            $results[$response.id] = $allItems
        }
    }

    return $results
}
