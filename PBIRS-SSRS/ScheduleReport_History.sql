SELECT 
	SUB.SubscriptionID,
	SUB.Report_OID,
	CAT.Path,
	CAT.Name,
	USR.username,
	SUB.Description AS SchedulName,
	SUB.EventType,
	HIST.SubscriptionHistoryID,
	HIST.StartTime,
	Hist.EndTime,
	DATEDIFF(SECOND,HIST.StartTime,Hist.EndTime) AS Dure,
	HIST.Status,
	HIST.Message,
	CASE
		WHEN HIST.Status = 0 THEN 'Data refresh finished sucessfully'
		WHEN HIST.Status = 1 THEN 'Data refresh is in progress'
		ELSE 'Error during refresh'
	END AS RESULT
FROM 
	dbo.Subscriptions SUB
	INNER JOIN dbo.Users USR ON USR.UserID = SUB.OwnerID
	INNER JOIN SubscriptionHistory HIST ON HIST.SubscriptionID = SUB.SubscriptionID
	INNER JOIN dbo.Catalog CAT ON CAT.ItemID = SUB.Report_OID