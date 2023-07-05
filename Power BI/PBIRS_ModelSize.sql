-- Romain Casteres
-- PBIRS Model Size

SELECT 
	c.ItemID,
	c.[Path],
	c.[Name] AS ReportName,
	ISNULL(cp.[Name], 'Root') AS ParentItem,
	CASE c.[Type]
		WHEN 1 THEN 'Folder'
		WHEN 2 THEN 'Report'
		WHEN 3 THEN 'Resources'
		WHEN 4 THEN 'Linked Report'
		WHEN 5 THEN 'Data Source'
		WHEN 6 THEN 'Report Model'
		WHEN 7 THEN 'Report Part'
		WHEN 8 THEN 'Shared dataset'
		WHEN 11 THEN 'KPI Card'
		WHEN 13 THEN 'PowerBI'
		ELSE CAST(c.[Type] AS VARCHAR(10))
	END AS ItemType,
	c.Property,
	c.[Description],
	c.[Hidden],
	cu.UserName AS CreatedBy,
	c.CreationDate,
	mu.UserName AS ModifiedBy,
	c.ModifiedDate,
	ISNULL(CAST(c.ContentSize AS FLOAT) / CAST((1024 * 1024) AS FLOAT), 0) AS ContentSizeMb
FROM dbo.[Catalog] c
    LEFT OUTER JOIN dbo.[Catalog] cp ON c.ParentID = cp.ItemID
    LEFT OUTER JOIN dbo.Users cu ON c.CreatedByID = cu.UserID
    LEFT OUTER JOIN dbo.Users mu ON c.ModifiedByID = mu.UserID
WHERE LEFT(c.[Path], 14) <> '/Users Folders'; 