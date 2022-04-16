--Create Table for Data

DROP TABLE IF EXISTS CarData
 
CREATE TABLE CarData (
    ReconditioningDate varchar(255),
    ReconditioningCost FLOAT,
    VehicleID varchar(255),
    Year varchar(255),
    Make varchar(255),
    Model varchar(255),
    TrimLine varchar(255),
    BodyStyle varchar(255),
    InteriorColor varchar(255),
    ExteriorColor varchar(255),
    Doors varchar(255),
    OdometerValue FLOAT,
    AcquisitionDate DATE,
    AcquisitionSource varchar(255),
    Blank varchar(255)
) ;

BULK INSERT CarData
FROM 'C:\Users\Emma DeJarnette\Documents\DATA for VSC\Carvana\CaseDataCarvananocommas.csv'
WITH (FIRSTROW = 2 --Removed Format = 'csv' and worked for whatever reason: https://github.com/Microsoft/sql-server-samples/issues/408
      
      , FIELDTERMINATOR = ',' -- heyyo you gotta do this:https://www.howtogeek.com/howto/21456/export-or-save-excel-files-with-pipe-or-other-delimiters-instead-of-commas/
      , ROWTERMINATOR = '\n');

-------------------------------------
-- Create Cleaned Final Data Table for Export to Tableau, Assign Distrubution Percentiles to two variables of interest (Reconditioning Cost and Odomoeter Value) 
Select *
    ,Round(PERCENT_RANK() OVER(Order by ReconditioningCost),2) as RCPercentile
    ,Round(PERCENT_RANK() OVER(Order by OdometerValue),2) as OdomPercentile 
FROM CarData
WHERE ReconditioningCost IS NOT NULL AND OdometerValue IS NOT NULL AND ReconditioningCost >0 AND OdometerValue >0; 

-- Determine Distinct Month and Year Combinations to show time range that data spans
SELECT DISTINCT(DATEPART(mm,AcquisitionDate)) as months, -- Cars acquired over the course of 5 Months: September (9) - January (1)
    (DATEPART(yy,AcquisitionDate)) as years 
     FROM CarData
        ORDER BY years ASC, months ASC

-- Using a nested subquery, orders the Average Reconditioning Cost per Month   
SELECT AVG(RCCost) as AvgRecondCost,
    Month1,
    Year1
FROM (SELECT DATEPART(mm,AcquisitionDate) AS Month1,
        DATEPART(yy,AcquisitionDate)  as Year1, 
        CAST(ReconditioningCost as FLOAT) as RCCost
        FROM CarData) AS cd 
WHERE Month1 IS NOT NULL
GROUP BY Month1, Year1
ORDER BY Year1 ASC, Month1 ASC


-- Using Aggregate Functions and Group By, determines Average Odometer Value and Reconditioning Cost per Body Style
SELECT BodyStyle,
    AVG(CAST(OdometerValue as FLOAT)) as AvgOdometer,
    AVG(CAST(ReconditioningCost as FLOAT)) as AvgRecondCost
FROM CarData
WHERE BodyStyle IS NOT NULL
GROUP BY BodyStyle

-- Using Window Functions, determines Average Odometer Value and Reconditioning Cost per Body Style and Make
SELECT BodyStyle,
    Make,
    OdometerValue,
    AVG(CAST(OdometerValue as FLOAT)) OVER(PARTITION BY Make,BodyStyle) as AvgOdometer,
    AVG(CAST(ReconditioningCost as FLOAT)) OVER(PARTITION BY Make,BodyStyle) as AvgRecondCost
FROM CarData
WHERE BodyStyle IS NOT NULL
ORDER BY BodyStyle, Make

-- Using Window Functions, determines Average Odometer Value and Reconditioning Cost per Year and Acquisition Source
SELECT DISTINCT [Year],
    AcquisitionSource,
    AVG(CAST(OdometerValue as FLOAT)) OVER(PARTITION BY [Year], AcquisitionSource) as AvgOdometerbyYRandSOURCE,
    AVG(CAST(ReconditioningCost as FLOAT)) OVER(PARTITION BY [Year],AcquisitionSource) as AvgRecondCostbyYRandSOURCE 
FROM CarData
WHERE [Year] IS NOT NULL

--Using Temptables and Correlated Subqueries, Counts number of instances a Make is above the median Reconditioning Cost for each year
DROP TABLE IF EXISTS #temptable3
 
SELECT a.[YEAR], 
    AVG(a.ReconditioningCost) as AVGRC,
    a.Make, 
    COUNT(a.Make) as [Count]
INTO #temptable3
FROM (SELECT * FROM CarData WHERE ReconditioningCost > 
        (SELECT AVG(CAST(ReconditioningCost as FLOAT)) FROM CarData)) as a 
GROUP BY [YEAR], Make


-- Using Temporary tables, Correlated Subqueries, and Joins, calculates percentage of each Make that is above the median Reconditioning Cost.
SELECT c.Make
, c.AboveAvgCt/c.TotalCt as PERCTotalAboveAVG 
FROM (SELECT  b.Make 
        , CAST(SUM(a.[Count]) as FLOAT) as AboveAvgCt
        , CAST(SUM(b.[TotalMake]) as FLOAT) as TotalCt
        FROM #temptable3 as a
        FULL JOIN (SELECT Make, Count(Make) as TotalMake FROM CarData GROUP BY Make) as b ON a.Make = b.Make    
        GROUP BY b.Make) as c
WHERE AboveAvgCt IS NOT NULL
ORDER BY PERCTotalAboveAVG DESC


-- Using a Self-Join and CASE WHEN statement, creates a flag to easily identify vehicles with a Reconditioning Cost above the Median

SELECT CarData.*
    , CASE WHEN a.VehicleID IS NOT NULL THEN 1 ELSE 0 END as AboveAvgRCFlag
FROM (SELECT * FROM CarData WHERE ReconditioningCost > 
        (SELECT AVG(CAST(ReconditioningCost as FLOAT)) FROM CarData)) as a 
RIGHT JOIN CarData ON CarData.VehicleID = a.VehicleID
WHERE CarData.OdometerValue  != 0 AND  CarData.ReconditioningCost !=0 AND CarData.OdometerValue IS NOT NULL


--LINEAR REGRESSION on Odometer Value (ind) and Reconditioning Cost (dep)
---Since SQL does not have regression functions as built-ins, we are going to manually input the equations.
Drop Table if exists #OdomReconRegress

select Make
        ,OdometerValue as x
       ,avg(OdometerValue) over () as x_bar
       ,ReconditioningCost as y
       , avg(ReconditioningCost) over () as y_bar
INTO #OdomReconRegress
from CarData
WHERE OdometerValue  != 0 AND ReconditioningCost !=0;


SELECT Slope
    ,(y_bar_max - x_bar_max * slope) as intercept
FROM(Select sum((x - x_bar) * (y - y_bar)) / sum((x - x_bar) * (x - x_bar)) as slope
    ,max(x_bar) as x_bar_max
    ,max(y_bar) as y_bar_max
    from #OdomReconRegress
    ) as s

-- Regression Line is y = 0.02x + 944.65
-- Will calculate R-squared and P-value in coming update