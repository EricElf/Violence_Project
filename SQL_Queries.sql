-- Formatting date column
ALTER TABLE mass_shooter 
ADD COLUMN Date_Formatted DATE;

UPDATE mass_shooter 
SET Date_Formatted = STR_TO_DATE(Full_Date, '%m/%d/%Y');
__________________________________________________________________________________________________________________________________________________________________
-- Creating North Star metrics

-- 1. Creating Overall Composite Risk Score 
WITH Scoring AS (
    SELECT 
        case_no,
        date_formatted,
        -- Family Background (10 points total)
        (CASE WHEN Parental_Divorce_Separation = 1 THEN 2 ELSE 0 END +
         CASE WHEN Parental_Death_in_Childhood = 1 THEN 3 ELSE 0 END +
         CASE WHEN Parental_Substance_Abuse = 1 THEN 2 ELSE 0 END +
         CASE WHEN Parent_Criminal_Record = 1 THEN 1 ELSE 0 END +
         CASE WHEN Family_Member_Incarcerated = 1 THEN 2 ELSE 0 END) AS Family_Background_Score,
        
        -- Childhood Trauma (20 points total, now includes bullying)
        (CASE WHEN Childhood_Trauma = 1 THEN 4 ELSE 0 END +
         CASE WHEN Physically_Abused = 1 THEN 4 ELSE 0 END +
         CASE WHEN Sexually_Abused = 1 THEN 5 ELSE 0 END +
         CASE WHEN Emotionally_Abused = 1 THEN 3 ELSE 0 END +
         CASE WHEN Neglected = 1 THEN 2 ELSE 0 END +
         CASE WHEN Bullied = 1 THEN 2 ELSE 0 END) AS Childhood_Trauma_Score,
        
        -- Psychological History (40 points total)
        (CASE WHEN Mental_Illness <> 'No evidence' THEN 6 ELSE 0 END +
         CASE WHEN Substance_Use IN ('Problem with alcohol', 'Other drugs') THEN 5 ELSE 0 END +
         CASE WHEN History_of_Physical_Altercations IS NOT NULL AND History_of_Physical_Altercations <> 'No evidence' THEN 6 ELSE 0 END +
         CASE WHEN History_of_Animal_Abuse = 1 THEN 3 ELSE 0 END +
         CASE WHEN History_of_Domestic_Abuse IS NOT NULL AND History_of_Domestic_Abuse <> 'No evidence' THEN 5 ELSE 0 END +
         CASE WHEN History_of_Sexual_Offenses = 1 THEN 6 ELSE 0 END +
         CASE WHEN Gang_Affiliation = 1 THEN 2 ELSE 0 END +
         CASE WHEN Terror_Group_Affiliation = 1 THEN 3 ELSE 0 END +
         CASE WHEN Known_Hate_Group_or_Chat_Room_Affiliation_Code = 1 THEN 3 ELSE 0 END +
         CASE WHEN Adult_Trauma IS NOT NULL AND Adult_Trauma <> 'No evidence' THEN 5 ELSE 0 END) AS Psychological_Behavioral_Score,
        
        -- Recent Stressors (30 points total)
        (CASE WHEN Recent_or_Ongoing_Stressor IS NOT NULL AND Recent_or_Ongoing_Stressor <> 'No evidence' THEN 4 ELSE 0 END +
         CASE WHEN Signs_of_Being_in_Crisis = 1 THEN 5 ELSE 0 END +
         CASE WHEN Crisis_Six_Months_or_Less = 1 THEN 4 ELSE 0 END +
         CASE WHEN Paranoia = 1 THEN 3 ELSE 0 END +
         CASE WHEN Rapid_Mood_Swings = 1 THEN 3 ELSE 0 END +
         CASE WHEN Isolation = 1 THEN 2 ELSE 0 END +
         CASE WHEN Abusive_Behavior = 1 THEN 4 ELSE 0 END +
         CASE WHEN Suicidality IS NOT NULL AND Suicidality <> 'No evidence' THEN 5 ELSE 0 END) AS Recent_Stressor_Score
    FROM mass_shooter
)
SELECT
    case_no,
    Family_Background_Score,
    Childhood_Trauma_Score,
    Psychological_Behavioral_Score,
    Recent_Stressor_Score,
    (Family_Background_Score + 
     Childhood_Trauma_Score + 
     Psychological_Behavioral_Score + 
     Recent_Stressor_Score) AS Overall_Composite_Risk_Score,
    CASE
        WHEN (Family_Background_Score + Childhood_Trauma_Score + Psychological_Behavioral_Score + Recent_Stressor_Score) >= 61 THEN 'Extreme Risk'
        WHEN (Family_Background_Score + Childhood_Trauma_Score + Psychological_Behavioral_Score + Recent_Stressor_Score) BETWEEN 41 AND 60 THEN 'High Risk'
        WHEN (Family_Background_Score + Childhood_Trauma_Score + Psychological_Behavioral_Score + Recent_Stressor_Score) BETWEEN 15 AND 40 THEN 'Moderate Risk'
        ELSE 'Lower Risk'
    END AS Risk_Category,
    EXTRACT(YEAR FROM date_formatted) AS Year
FROM Scoring
ORDER BY Overall_Composite_Risk_Score DESC;

-- IOR with year
WITH Prior_System_Contact AS (
    SELECT 
        Case_No,
        (CASE WHEN Known_to_Police_or_FBI = 1 THEN 2 ELSE 0 END +
         CASE WHEN Criminal_Record = 1 THEN 3 ELSE 0 END +
         CASE WHEN Prior_Hospitalization = 1 THEN 2 ELSE 0 END +
         CASE WHEN Suicidality IS NOT NULL AND Suicidality <> 'No evidence' THEN 2 ELSE 0 END +
         CASE WHEN Prior_Counseling = 1 THEN 1 ELSE 0 END +
         CASE WHEN Psychiatric_Medication IS NOT NULL THEN 2 ELSE 0 END +
         CASE WHEN History_of_Physical_Altercations IS NOT NULL AND History_of_Physical_Altercations <> 'No evidence' THEN 1 ELSE 0 END +
         CASE WHEN History_of_Domestic_Abuse IS NOT NULL AND History_of_Domestic_Abuse <> 'No evidence' THEN 2 ELSE 0 END +
         CASE WHEN Gang_Affiliation = 1 THEN 2 ELSE 0 END
        ) AS Prior_Contact_Score
    FROM Mass_Shooter
),

Signs_of_Crisis AS (
    SELECT 
        Case_No,
        (CASE WHEN Signs_of_Being_in_Crisis = 1 THEN 2 ELSE 0 END +
         CASE WHEN Crisis_Six_Months_or_Less = 1 THEN 1 ELSE 0 END +
         CASE WHEN Paranoia = 1 THEN 1 ELSE 0 END +
         CASE WHEN Rapid_Mood_Swings = 1 THEN 1 ELSE 0 END +
         CASE WHEN Isolation = 1 THEN 1 ELSE 0 END +
         CASE WHEN Abusive_Behavior = 1 THEN 1 ELSE 0 END +
         CASE WHEN Recent_or_Ongoing_Stressor IS NOT NULL AND Recent_or_Ongoing_Stressor <> 'No evidence' THEN 1 ELSE 0 END
        ) AS Crisis_Score
    FROM Mass_Shooter
),

Leakage AS (
    SELECT 
        Case_No,
        CASE WHEN Leakage = 1 THEN 
             3 + -- Base score for leakage occurring
             CASE 
                 WHEN Leakage_Who LIKE '%Police%' OR Leakage_Who LIKE '%Mental health%' THEN 2
                 WHEN Leakage_Who IS NOT NULL THEN 1 
                 ELSE 0 
             END +
             CASE 
                 WHEN Leakage_How IN ('Direct Threat', 'Manifesto') THEN 2
                 WHEN Leakage_How IS NOT NULL THEN 1
                 ELSE 0
             END
        ELSE 0 END AS Leakage_Score
    FROM Mass_Shooter
)

SELECT 
    ms.Case_No,
    YEAR(ms.date_formatted) AS Year,  -- Added this line to extract the year
    COALESCE(psc.Prior_Contact_Score, 0) AS Prior_Contact_Score,
    COALESCE(sc.Crisis_Score, 0) AS Crisis_Score,
    COALESCE(l.Leakage_Score, 0) AS Leakage_Score,
    COALESCE(psc.Prior_Contact_Score, 0) + 
    COALESCE(sc.Crisis_Score, 0) + 
    COALESCE(l.Leakage_Score, 0) AS Intervention_Opportunity_Rate,
    CASE 
        WHEN COALESCE(psc.Prior_Contact_Score, 0) + 
             COALESCE(sc.Crisis_Score, 0) + 
             COALESCE(l.Leakage_Score, 0) >= 12 THEN 'Severe missed intervention'
        WHEN COALESCE(psc.Prior_Contact_Score, 0) + 
             COALESCE(sc.Crisis_Score, 0) + 
             COALESCE(l.Leakage_Score, 0) BETWEEN 8 AND 11 THEN 'Moderate missed intervention'
        WHEN COALESCE(psc.Prior_Contact_Score, 0) + 
             COALESCE(sc.Crisis_Score, 0) + 
             COALESCE(l.Leakage_Score, 0) BETWEEN 4 AND 7 THEN 'Limited intervention opportunities'
        ELSE 'No clear intervention opportunity'
    END AS Intervention_Category
FROM Mass_Shooter ms
LEFT JOIN Prior_System_Contact psc ON ms.Case_No = psc.Case_No
LEFT JOIN Signs_of_Crisis sc ON ms.Case_No = sc.Case_No
LEFT JOIN Leakage l ON ms.Case_No = l.Case_No
ORDER BY Intervention_Opportunity_Rate DESC;


-- 2. Calculating analysis for composite Risk score per event
WITH Scoring AS (
    SELECT 
        case_no,
        (CASE WHEN Parental_Divorce_Separation = 1 THEN 2 ELSE 0 END +
         CASE WHEN Parental_Death_in_Childhood = 1 THEN 3 ELSE 0 END +
         CASE WHEN Parental_Substance_Abuse = 1 THEN 2 ELSE 0 END +
         CASE WHEN Parent_Criminal_Record = 1 THEN 1 ELSE 0 END +
         CASE WHEN Family_Member_Incarcerated = 1 THEN 2 ELSE 0 END) AS Family_Background_Score,
        
        (CASE WHEN Childhood_Trauma = 1 THEN 4 ELSE 0 END +
         CASE WHEN Physically_Abused = 1 THEN 4 ELSE 0 END +
         CASE WHEN Sexually_Abused = 1 THEN 5 ELSE 0 END +
         CASE WHEN Emotionally_Abused = 1 THEN 3 ELSE 0 END +
         CASE WHEN Neglected = 1 THEN 2 ELSE 0 END +
         CASE WHEN Bullied = 1 THEN 2 ELSE 0 END) AS Childhood_Trauma_Score,
        
        (CASE WHEN Mental_Illness <> 'No evidence' THEN 6 ELSE 0 END +
         CASE WHEN Substance_Use IN ('Problem with alcohol', 'Other drugs') THEN 5 ELSE 0 END +
         CASE WHEN History_of_Physical_Altercations IS NOT NULL AND History_of_Physical_Altercations <> 'No evidence' THEN 6 ELSE 0 END +
         CASE WHEN History_of_Animal_Abuse = 1 THEN 3 ELSE 0 END +
         CASE WHEN History_of_Domestic_Abuse IS NOT NULL AND History_of_Domestic_Abuse <> 'No evidence' THEN 5 ELSE 0 END +
         CASE WHEN History_of_Sexual_Offenses = 1 THEN 6 ELSE 0 END +
         CASE WHEN Gang_Affiliation = 1 THEN 2 ELSE 0 END +
         CASE WHEN Terror_Group_Affiliation = 1 THEN 3 ELSE 0 END +
         CASE WHEN Known_Hate_Group_or_Chat_Room_Affiliation_Code = 1 THEN 3 ELSE 0 END +
         CASE WHEN Adult_Trauma IS NOT NULL AND Adult_Trauma <> 'No evidence' THEN 5 ELSE 0 END) AS Psychological_Behavioral_Score,
        
        (CASE WHEN Recent_or_Ongoing_Stressor IS NOT NULL AND Recent_or_Ongoing_Stressor <> 'No evidence' THEN 4 ELSE 0 END +
         CASE WHEN Signs_of_Being_in_Crisis = 1 THEN 5 ELSE 0 END +
         CASE WHEN Crisis_Six_Months_or_Less = 1 THEN 4 ELSE 0 END +
         CASE WHEN Paranoia = 1 THEN 3 ELSE 0 END +
         CASE WHEN Rapid_Mood_Swings = 1 THEN 3 ELSE 0 END +
         CASE WHEN Isolation = 1 THEN 2 ELSE 0 END +
         CASE WHEN Abusive_Behavior = 1 THEN 4 ELSE 0 END +
         CASE WHEN Suicidality IS NOT NULL AND Suicidality <> 'No evidence' THEN 5 ELSE 0 END) AS Recent_Stressor_Score
    FROM mass_shooter
),
Composite_Scores AS (
    SELECT
        case_no,
        (Family_Background_Score + 
         Childhood_Trauma_Score + 
         Psychological_Behavioral_Score + 
         Recent_Stressor_Score) AS Overall_Composite_Risk_Score
    FROM Scoring
)
SELECT 
    AVG(Overall_Composite_Risk_Score) AS Average_Composite_Risk_Score,
    MIN(Overall_Composite_Risk_Score) AS Minimum_Score,
    MAX(Overall_Composite_Risk_Score) AS Maximum_Score,
    STDDEV(Overall_Composite_Risk_Score) AS Score_Standard_Deviation,
    COUNT(*) AS Total_Events,
    -- Breakdown by risk category percentages
    ROUND(100.0 * SUM(CASE WHEN Overall_Composite_Risk_Score >= 80 THEN 1 ELSE 0 END) / COUNT(*), 1) AS Percent_Extreme_Risk,
    ROUND(100.0 * SUM(CASE WHEN Overall_Composite_Risk_Score BETWEEN 60 AND 79 THEN 1 ELSE 0 END) / COUNT(*), 1) AS Percent_High_Risk,
    ROUND(100.0 * SUM(CASE WHEN Overall_Composite_Risk_Score BETWEEN 40 AND 59 THEN 1 ELSE 0 END) / COUNT(*), 1) AS Percent_Moderate_Risk,
    ROUND(100.0 * SUM(CASE WHEN Overall_Composite_Risk_Score < 40 THEN 1 ELSE 0 END) / COUNT(*), 1) AS Percent_Lower_Risk
FROM Composite_Scores;

-- 3. Creating firearm acquisition risk score
SELECT 
    fu.Case__, 
    fu.Full_Date, 
    COALESCE(
        CASE WHEN fu.Full_Date IS NOT NULL THEN YEAR(fu.Full_Date) END,
        YEAR(ms.date_formatted),
        CASE 
            WHEN fu.When_Obtained REGEXP '[0-9]{4}' THEN 
                CAST(REGEXP_SUBSTR(fu.When_Obtained, '[0-9]{4}') AS UNSIGNED)
            ELSE NULL
        END
    ) AS Year,
    fu.Make_and_Model, 
    fu.Classification, 
    fu.Caliber, 
    fu.Used_in_Shooting_,
    fu.Modified,
    fu.Large_Capacity_Magazine,
    fu.Extended_Magazine,
    fu.When_Obtained,
    fu.Legal_Purchase,
    fu.Illegal_Purchase,
    fu.Assembled_with_Legal_Parts_,
    fu.Gifted,
    fu.Theft,
    fu.Unknown,
    (
        -- Acquisition Method Risk
        (COALESCE(fu.Illegal_Purchase, 0) * 5) +
        (COALESCE(fu.Theft, 0) * 5) +
        (COALESCE(fu.Gifted, 0) * 3) +
        (COALESCE(fu.Assembled_with_Legal_Parts_, 0) * 3) +
        (COALESCE(fu.Legal_Purchase, 0) * 1) +
        (COALESCE(fu.Unknown, 0) * 2) +

        -- Firearm Modification Risk
        (COALESCE(fu.Modified, 0) * 5) +
        (COALESCE(fu.Large_Capacity_Magazine, 0) * 3) +
        (COALESCE(fu.Extended_Magazine, 0) * 3) +

        -- Firearm Classification Risk
        CASE 
            WHEN fu.Classification = 'Handgun' THEN 2
            WHEN fu.Classification = 'Rifle' THEN 3
            WHEN fu.Classification = 'Shotgun' THEN 2
            WHEN fu.Classification = 'Assault Rifle' THEN 5
            ELSE 1 
        END
    ) AS Firearm_Acquisition_Risk_Score
FROM firearms_used fu
LEFT JOIN mass_shooter ms ON fu.Case__ = ms.case_no
ORDER BY Firearm_Acquisition_Risk_Score DESC;

-- 4. Creating the Intervention Opportunity Rate (IOR)
WITH Prior_System_Contact AS (
    SELECT 
        Case_No,
        (CASE WHEN Known_to_Police_or_FBI = 1 THEN 2 ELSE 0 END +
         CASE WHEN Criminal_Record = 1 THEN 3 ELSE 0 END +
         CASE WHEN Prior_Hospitalization = 1 THEN 2 ELSE 0 END +
         CASE WHEN Suicidality IS NOT NULL AND Suicidality <> 'No evidence' THEN 2 ELSE 0 END +
         CASE WHEN Prior_Counseling = 1 THEN 1 ELSE 0 END +
         CASE WHEN Psychiatric_Medication IS NOT NULL THEN 2 ELSE 0 END +
         CASE WHEN History_of_Physical_Altercations IS NOT NULL AND History_of_Physical_Altercations <> 'No evidence' THEN 1 ELSE 0 END +
         CASE WHEN History_of_Domestic_Abuse IS NOT NULL AND History_of_Domestic_Abuse <> 'No evidence' THEN 2 ELSE 0 END +
         CASE WHEN Gang_Affiliation = 1 THEN 2 ELSE 0 END
        ) AS Prior_Contact_Score
    FROM Mass_Shooter
),

Signs_of_Crisis AS (
    SELECT 
        Case_No,
        (CASE WHEN Signs_of_Being_in_Crisis = 1 THEN 2 ELSE 0 END +
         CASE WHEN Crisis_Six_Months_or_Less = 1 THEN 1 ELSE 0 END +
         CASE WHEN Paranoia = 1 THEN 1 ELSE 0 END +
         CASE WHEN Rapid_Mood_Swings = 1 THEN 1 ELSE 0 END +
         CASE WHEN Isolation = 1 THEN 1 ELSE 0 END +
         CASE WHEN Abusive_Behavior = 1 THEN 1 ELSE 0 END +
         CASE WHEN Recent_or_Ongoing_Stressor IS NOT NULL AND Recent_or_Ongoing_Stressor <> 'No evidence' THEN 1 ELSE 0 END
        ) AS Crisis_Score
    FROM Mass_Shooter
),

Leakage AS (
    SELECT 
        Case_No,
        CASE WHEN Leakage = 1 THEN 
             3 + -- Base score for leakage occurring
             CASE 
                 WHEN Leakage_Who LIKE '%Police%' OR Leakage_Who LIKE '%Mental health%' THEN 2
                 WHEN Leakage_Who IS NOT NULL THEN 1 
                 ELSE 0 
             END +
             CASE 
                 WHEN Leakage_How IN ('Direct Threat', 'Manifesto') THEN 2
                 WHEN Leakage_How IS NOT NULL THEN 1
                 ELSE 0
             END
        ELSE 0 END AS Leakage_Score
    FROM Mass_Shooter
)

SELECT 
    ms.Case_No,
    COALESCE(psc.Prior_Contact_Score, 0) AS Prior_Contact_Score,
    COALESCE(sc.Crisis_Score, 0) AS Crisis_Score,
    COALESCE(l.Leakage_Score, 0) AS Leakage_Score,
    COALESCE(psc.Prior_Contact_Score, 0) + 
    COALESCE(sc.Crisis_Score, 0) + 
    COALESCE(l.Leakage_Score, 0) AS Intervention_Opportunity_Rate,
    CASE 
        WHEN COALESCE(psc.Prior_Contact_Score, 0) + 
             COALESCE(sc.Crisis_Score, 0) + 
             COALESCE(l.Leakage_Score, 0) >= 12 THEN 'Severe missed intervention'
        WHEN COALESCE(psc.Prior_Contact_Score, 0) + 
             COALESCE(sc.Crisis_Score, 0) + 
             COALESCE(l.Leakage_Score, 0) BETWEEN 8 AND 11 THEN 'Moderate missed intervention'
        WHEN COALESCE(psc.Prior_Contact_Score, 0) + 
             COALESCE(sc.Crisis_Score, 0) + 
             COALESCE(l.Leakage_Score, 0) BETWEEN 4 AND 7 THEN 'Limited intervention opportunities'
        ELSE 'No clear intervention opportunity'
    END AS Intervention_Category
FROM Mass_Shooter ms
LEFT JOIN Prior_System_Contact psc ON ms.Case_No = psc.Case_No
LEFT JOIN Signs_of_Crisis sc ON ms.Case_No = sc.Case_No
LEFT JOIN Leakage l ON ms.Case_No = l.Case_No
ORDER BY Intervention_Opportunity_Rate DESC;


-- 5. Create Motive Risk Score
WITH Motive_Scoring AS (
    SELECT 
        ms.Case_No,
        ms.date_formatted,
        -- Explicit Hate Motives
        CASE WHEN ms.Motive__Racism_Xenophobia_Code = 1 THEN 8 ELSE 0 END +
        CASE WHEN ms.Motive__Religious_Hate_Code = 1 THEN 8 ELSE 0 END +
        CASE WHEN ms.Motive__Misogyny = 1 THEN 6 ELSE 0 END +
        CASE WHEN ms.Motive__Homophobia = 1 THEN 6 ELSE 0 END +
        CASE WHEN ms.Known_Prejudices IS NOT NULL AND ms.Known_Prejudices <> 'No evidence' THEN 4 ELSE 0 END AS Hate_Motive_Score,
        
        -- Personal Grievances
        CASE WHEN ms.Motive__Employment_Issue = 1 THEN 5 ELSE 0 END +
        CASE WHEN ms.Motive__Relationship_Issue = 1 THEN 5 ELSE 0 END +
        CASE WHEN ms.Motive__Interpersonal_Conflict = 1 THEN 4 ELSE 0 END AS Grievance_Motive_Score,
        
        -- Other Documented Motives
        CASE WHEN ms.Motive__Fame_Seeking = 1 THEN 7 ELSE 0 END +
        CASE WHEN ms.Motive__Economic_Issue = 1 THEN 3 ELSE 0 END +
        CASE WHEN ms.Motive__Legal_Issue = 1 THEN 3 ELSE 0 END +
        CASE WHEN ms.Motive__Other_Code = 1 THEN 2 ELSE 0 END AS Other_Motive_Score
    FROM mass_shooter ms
)
SELECT 
    Case_No,
    YEAR(date_formatted) AS Year,  -- Added year extraction
    Hate_Motive_Score,
    Grievance_Motive_Score,
    Other_Motive_Score,
    (Hate_Motive_Score + Grievance_Motive_Score + Other_Motive_Score) AS Total_Motive_Risk_Score,
    CASE
        WHEN (Hate_Motive_Score + Grievance_Motive_Score + Other_Motive_Score) >= 15 THEN 'High Risk (Hate/Extremism)'
        WHEN (Hate_Motive_Score + Grievance_Motive_Score + Other_Motive_Score) BETWEEN 10 AND 14 THEN 'Moderate Risk (Targeted Grievance)'
        ELSE 'Situational/Opportunistic'
    END AS Motive_Risk_Category
FROM Motive_Scoring
ORDER BY Total_Motive_Risk_Score DESC;

__________________________________________________________________________________________________________________________________________________________________

-- 1. Overall Trends: What are the patterns in mass shootings?

-- Shootings per year
SELECT 
    YEAR(date_formatted) AS Year, 
    COUNT(Case_No) AS Total_Incidents
FROM mass_shooter
GROUP BY Year
ORDER BY Year ASC;

-- Which month has the most mass shootings
SELECT 
    MONTH(date_formatted) AS Month, 
    COUNT(Case_No) AS Total_Incidents
FROM mass_shooter
GROUP BY Month
ORDER BY Total_Incidents DESC;

-- Which season has the most mass shootings
SELECT 
    CASE 
        WHEN MONTH(date_formatted) IN (12, 1, 2) THEN 'Winter'
        WHEN MONTH(date_formatted) IN (3, 4, 5) THEN 'Spring'
        WHEN MONTH(date_formatted) IN (6, 7, 8) THEN 'Summer'
        WHEN MONTH(date_formatted) IN (9, 10, 11) THEN 'Fall'
    END AS Season, 
    COUNT(Case_No) AS Total_Incidents
FROM mass_shooter
GROUP BY Season
ORDER BY Total_Incidents DESC;

-- Day of the week most shootings occur
Select Day_of_Week, count(day_of_week) as num_of_incidents
from mass_shooter	
group by Day_of_Week

-- Which state has the most mass shootings
Select State, count(state) as incidents
from mass_shooter
group by state
order by incidents desc

-- Region with the most incidents
Select region, count(region) as incidents
from mass_shooter
group by region
order by incidents desc 

-- Top 10 cities with most incidents
Select city, count(city) as incidents
from mass_shooter
group by city
order by incidents desc
Limit 10

-- top 6 most common locations of shootings
Select location, count(location) as incidents
from mass_shooter
group by location
order by incidents desc	

-- Which age group has the most shooters
SELECT 
    CASE 
        WHEN age < 18 THEN 'Under 18'
        WHEN age BETWEEN 18 AND 24 THEN '18-24'
        WHEN age BETWEEN 25 AND 34 THEN '25-34'
        WHEN age BETWEEN 35 AND 44 THEN '35-44'
        WHEN age BETWEEN 45 AND 54 THEN '45-54'
        WHEN age BETWEEN 55 AND 64 THEN '55-64'
        WHEN age >= 65 THEN '65+'
        ELSE 'Unknown'
    END AS Age_Group,
    COUNT(*) AS Group_Count
FROM mass_shooter
GROUP BY Age_Group
ORDER BY Group_Count DESC;

-- Which gender commits the most shootings?
Select gender, count(gender) 
from mass_shooter	
group by gender

-- Which race commits the most shootings?
Select race, count(race) as num_of_incidents
from mass_shooter	
group by race
order by num_of_incidents desc

-- Which relgion commits the most shootings?
Select immigrant, count(immigrant) as num_of_incidents
from mass_shooter	
group by immigrant
order by num_of_incidents desc


-- Average number of victims per incident
SELECT 
    AVG(number_killed + number_injured) AS avg_victims_per_incident
FROM mass_shooter;


----------------------------------------------------------------------------------------------------------------------------------------
-- 2. Growth Rates: How are mass shootings changing over time?

-- How has firearm acquisition (legal vs illegal) trended over time? 
SELECT 
    YEAR(f.Date_Formatted) AS Year, 
    SUM(CASE WHEN f.Legal_Purchase = 'Yes' THEN 1 ELSE 0 END) AS Legal_Purchases,
    SUM(CASE WHEN f.Illegal_Purchase = 'Yes' THEN 1 ELSE 0 END) AS Illegal_Purchases,
    ROUND(SUM(CASE WHEN f.Illegal_Purchase = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS Illegal_Acquisition_Percentage
FROM firearms_used f
JOIN mass_shooter m ON f.Case__= m.Case_No
GROUP BY YEAR(f.Date_Formatted)
ORDER BY Year;

-- How has the Overall Composite Risk Score changed over time?

WITH Scoring AS (
    SELECT 
        case_no,
        YEAR(Date_Formatted) AS Year,  -- Extract the year from the date
        -- Family Background Score (Total points: 10)
        (CASE WHEN Parental_Divorce_Separation = 1 THEN 2 ELSE 0 END +  -- Medium significance
         CASE WHEN Parental_Death_in_Childhood = 1 THEN 3 ELSE 0 END +  -- High significance
         CASE WHEN Parental_Substance_Abuse = 1 THEN 2 ELSE 0 END +     -- Medium significance
         CASE WHEN Parent_Criminal_Record = 1 THEN 1 ELSE 0 END +      -- Low significance
         CASE WHEN Family_Member_Incarcerated = 1 THEN 2 ELSE 0 END    -- Medium significance
        ) AS Family_Background_Score,
        
        -- Childhood Trauma and Abuse Score (Total points: 20)
        (CASE WHEN Childhood_Trauma = 1 THEN 4 ELSE 0 END +            -- High significance
         CASE WHEN Physically_Abused = 1 THEN 4 ELSE 0 END +           -- High significance
         CASE WHEN Sexually_Abused = 1 THEN 5 ELSE 0 END +             -- Very high significance
         CASE WHEN Emotionally_Abused = 1 THEN 3 ELSE 0 END +          -- Medium significance
         CASE WHEN Neglected = 1 THEN 4 ELSE 0 END                     -- High significance
        ) AS Childhood_Trauma_Score,
        
        -- Psychological and Behavioral History Score (Total points: 40)
        (CASE WHEN Mental_Illness <> 'No evidence' THEN 6 ELSE 0 END +  -- Very high significance
         CASE WHEN Substance_Use IN ('Problem with alcohol', 'Other drugs') THEN 5 ELSE 0 END +  -- High significance
         CASE WHEN History_of_Physical_Altercations IS NOT NULL AND History_of_Physical_Altercations <> 'No evidence' THEN 6 ELSE 0 END +  -- Very high significance
         CASE WHEN History_of_Animal_Abuse = 1 THEN 3 ELSE 0 END +      -- Medium significance
         CASE WHEN History_of_Domestic_Abuse IS NOT NULL AND History_of_Domestic_Abuse <> 'No evidence' THEN 5 ELSE 0 END +    -- High significance
         CASE WHEN History_of_Sexual_Offenses = 1 THEN 6 ELSE 0 END +   -- Very high significance
         CASE WHEN Gang_Affiliation = 1 THEN 2 ELSE 0 END +             -- Low significance
         CASE WHEN Terror_Group_Affiliation = 1 THEN 3 ELSE 0 END +     -- Medium significance
         CASE WHEN Known_Hate_Group_or_Chat_Room_Affiliation_Code = 1 THEN 3 ELSE 0 END +  -- Medium significance
         CASE WHEN Adult_Trauma IS NOT NULL AND Adult_Trauma <> 'No evidence' THEN 5 ELSE 0 END  -- High significance
        ) AS Psychological_Behavioral_Score,
        
        -- Recent Stressors and Crisis Indicators Score (Total points: 30)
        (CASE WHEN Recent_or_Ongoing_Stressor IS NOT NULL AND Recent_or_Ongoing_Stressor <> 'No evidence' THEN 4 ELSE 0 END +  -- High significance
         CASE WHEN Signs_of_Being_in_Crisis = 1 THEN 5 ELSE 0 END +    -- Very high significance
         CASE WHEN Crisis_Six_Months_or_Less = 1 THEN 4 ELSE 0 END +   -- High significance
         CASE WHEN Paranoia = 1 THEN 3 ELSE 0 END +                    -- Medium significance
         CASE WHEN Rapid_Mood_Swings = 1 THEN 3 ELSE 0 END +           -- Medium significance
         CASE WHEN Isolation = 1 THEN 2 ELSE 0 END +                   -- Low significance
         CASE WHEN Abusive_Behavior = 1 THEN 4 ELSE 0 END +            -- High significance
         CASE WHEN Suicidality IS NOT NULL AND Suicidality <> 'No evidence' THEN 5 ELSE 0 END  -- Very high significance
        ) AS Recent_Stressor_Score
    FROM mass_shooter
),
Overall_Scoring AS (
    SELECT
        case_no,
        Year,
        (Family_Background_Score + 
         Childhood_Trauma_Score + 
         Psychological_Behavioral_Score + 
         Recent_Stressor_Score) AS Overall_Composite_Risk_Score
    FROM Scoring
)
SELECT
    Year,
    AVG(Overall_Composite_Risk_Score) AS Avg_Overall_Composite_Risk_Score
FROM Overall_Scoring
GROUP BY Year
ORDER BY Year;

-- Are certain types of firearms becoming more common? Year over Year comparison of classifications 
SELECT 
    f.Classification, 
    YEAR(STR_TO_DATE(m.Full_Date, '%m/%d/%Y')) AS Year, 
    COUNT(*) AS Firearm_Count,
    ROUND((COUNT(*) - LAG(COUNT(*)) OVER (PARTITION BY f.Classification ORDER BY YEAR(STR_TO_DATE(m.Full_Date, '%m/%d/%Y')))) * 100.0 / 
          NULLIF(LAG(COUNT(*)) OVER (PARTITION BY f.Classification ORDER BY YEAR(STR_TO_DATE(m.Full_Date, '%m/%d/%Y'))), 0), 2) 
          AS YoY_Growth_Rate
FROM firearms_used f
JOIN mass_shooter m ON f.Case__ = m.Case_No
WHERE m.Full_Date IS NOT NULL
GROUP BY f.Classification, Year
ORDER BY f.Classification, Year;


-- Top 5 years with the Highest Growth in Mass Shootings (YoY Growth Rate)
SELECT 
    Year,
    Total_Incidents,
    LAG(Total_Incidents) OVER (ORDER BY Year) AS Previous_Year_Incidents,
    ROUND(((Total_Incidents - LAG(Total_Incidents) OVER (ORDER BY Year)) / 
        NULLIF(LAG(Total_Incidents) OVER (ORDER BY Year), 0)) * 100, 2) AS YoY_Growth_Percentage
FROM (
    SELECT 
        YEAR(date_formatted) AS Year, 
        COUNT(Case_No) AS Total_Incidents
    FROM mass_shooter
    GROUP BY Year
) AS Subquery
ORDER BY YoY_Growth_Percentage DESC
LIMIT 5;

-- What is the growth rate between decades?

WITH DecadeCounts AS (
    SELECT 
        CONCAT(FLOOR(YEAR(Date_Formatted) / 10) * 10, 's') AS Decade,
        COUNT(DISTINCT Case_No) AS Incident_Count,
        MIN(YEAR(Date_Formatted)) AS Start_Year,
        MAX(YEAR(Date_Formatted)) AS End_Year
    FROM Mass_Shooter
    WHERE YEAR(Date_Formatted) BETWEEN 1967 AND 2024
    GROUP BY CONCAT(FLOOR(YEAR(Date_Formatted) / 10) * 10, 's')
),
GrowthRates AS (
    SELECT
        Decade,
        Incident_Count,
        Start_Year,
        End_Year,
        -- Annualized rate accounting for incomplete decades
        ROUND(Incident_Count * 1.0 / (End_Year - Start_Year + 1), 2) AS Annual_Rate,
        -- Previous decade values for comparison
        LAG(Incident_Count, 1) OVER (ORDER BY Start_Year) AS Prev_Decade_Count,
        LAG(ROUND(Incident_Count * 1.0 / (End_Year - Start_Year + 1), 2), 1) 
            OVER (ORDER BY Start_Year) AS Prev_Decade_Annual_Rate
    FROM DecadeCounts
)
SELECT
    Decade,
    CONCAT(Start_Year, '-', End_Year) AS Years,
    Incident_Count AS Total_Incidents,
    Annual_Rate AS Incidents_Per_Year,
    -- Raw count growth
    CASE 
        WHEN Decade = '1960s' THEN 'Baseline'
        ELSE CONCAT(
            Incident_Count - Prev_Decade_Count, 
            ' (', 
            ROUND(((Incident_Count * 1.0 / NULLIF(Prev_Decade_Count, 0)) - 1) * 100, 1),
            '%)'
        )
    END AS Count_Growth_From_Previous_Decade,
    -- Annualized rate growth
    CASE 
        WHEN Decade = '1960s' THEN 'Baseline'
        ELSE CONCAT(
            ROUND(Annual_Rate - Prev_Decade_Annual_Rate, 2),
            ' (', 
            ROUND(((Annual_Rate / NULLIF(Prev_Decade_Annual_Rate, 0)) - 1) * 100, 1),
            '%)'
        )
    END AS Annualized_Rate_Growth
FROM GrowthRates
ORDER BY Start_Year;


________________________________________________________________________________________________________________--
-- Performance Measurement: What factors drive higher victim counts?


-- Do certain firearm types (semi-automatic rifles, modified weapons) result in higher casualties?
SELECT 
    f.Classification AS Firearm_Type,
    CASE 
        WHEN f.Legal_Purchase > 0 THEN 'Legal'
        WHEN f.Illegal_Purchase > 0 THEN 'Illegal'
        WHEN f.Legal_Purchase = 0 AND f.Illegal_Purchase = 0 THEN 'Unknown/Mixed'
        ELSE 'Unknown'
    END AS Legal_Status,
    AVG(m.Number_Killed) AS Avg_Killed,
    AVG(m.Number_Injured) AS Avg_Injured,
    AVG(m.Number_Killed + m.Number_Injured) AS Avg_Total_Victims,
    COUNT(*) AS Incident_Count
FROM firearms_used f
JOIN mass_shooter m ON f.Case__ = m.Case_No
WHERE f.Legal_Purchase IS NOT NULL OR f.Illegal_Purchase IS NOT NULL
GROUP BY f.Classification, 
    CASE 
        WHEN f.Legal_Purchase > 0 THEN 'Legal'
        WHEN f.Illegal_Purchase > 0 THEN 'Illegal'
        WHEN f.Legal_Purchase = 0 AND f.Illegal_Purchase = 0 THEN 'Unknown/Mixed'
        ELSE 'Unknown'
    END
ORDER BY Avg_Total_Victims DESC;

-- Simplified legal status comparison (all firearm types combined)
SELECT 
    CASE 
        WHEN f.Legal_Purchase > 0 THEN 'Legal'
        WHEN f.Illegal_Purchase > 0 THEN 'Illegal'
        WHEN f.Legal_Purchase = 0 AND f.Illegal_Purchase = 0 THEN 'Unknown/Mixed'
        ELSE 'Unknown'
    END AS Legal_Status,
    AVG(m.Number_Killed) AS Avg_Killed,
    AVG(m.Number_Injured) AS Avg_Injured,
    AVG(m.Number_Killed + m.Number_Injured) AS Avg_Total_Victims,
    COUNT(*) AS Incident_Count,
    SUM(f.Legal_Purchase) AS Total_Legal_Firearms,
    SUM(f.Illegal_Purchase) AS Total_Illegal_Firearms
FROM firearms_used f
JOIN mass_shooter m ON f.Case__ = m.Case_No
WHERE f.Legal_Purchase IS NOT NULL OR f.Illegal_Purchase IS NOT NULL
GROUP BY CASE 
        WHEN f.Legal_Purchase > 0 THEN 'Legal'
        WHEN f.Illegal_Purchase > 0 THEN 'Illegal'
        WHEN f.Legal_Purchase = 0 AND f.Illegal_Purchase = 0 THEN 'Unknown/Mixed'
        ELSE 'Unknown'
    END
ORDER BY Avg_Total_Victims DESC;


-- Do shooters with a criminal record or known mental illness cause more severe incidents?
-- criminal record
SELECT 
    Criminal_Record,
    COUNT(*) AS Total_Incidents,
    SUM(Number_Killed) AS Total_Killed,
    SUM(Number_Injured) AS Total_Injured,
    SUM(Number_Killed + Number_Injured) AS Total_Victims,
    ROUND(AVG(Number_Killed + Number_Injured), 2) AS Avg_Victims_Per_Incident
FROM Mass_Shooter
GROUP BY Criminal_Record;

-- mental illness
SELECT 
    Mental_Illness,
    COUNT(*) AS Total_Incidents,
    SUM(Number_Killed) AS Total_Killed,
    SUM(Number_Injured) AS Total_Injured,
    SUM(Number_Killed + Number_Injured) AS Total_Victims,
    ROUND(AVG(Number_Killed + Number_Injured), 2) AS Avg_Victims_Per_Incident
FROM Mass_Shooter
GROUP BY Mental_Illness
ORDER BY Total_Victims DESC;

-- How many shooters had prior police or mental health contact but no intervention?

SELECT
    COUNT(*) AS Shooters_With_Prior_Contact_But_No_Effective_Intervention
FROM
    mass_shooter
WHERE
    (Known_to_Police_or_FBI = 1 OR
     Prior_Hospitalization = 1 OR
     Prior_Counseling = 1);
     
-- What percentage of cases involved leakage (pre-incident warnings)?
SELECT 
    (COUNT(CASE WHEN Leakage = 1 THEN 1 END) * 100.0 / COUNT(*)) AS Leakage_Percentage
FROM mass_shooter;

________________________________________________________________________________________________________________________________
-- 4. KPI Reporting: How do key risk factors correlate with incidents?


-- How do the four categories of risk factors (family background, childhood trauma, psychological and behavioral history, and recent stressors) 
-- contribute to the Overall Composite Risk Score, and which category is the strongest predictor of mass violence?

WITH Scoring AS (
    SELECT 
        case_no,
        -- Family Background Score (Total points: 10)
        (CASE WHEN Parental_Divorce_Separation = 1 THEN 2 ELSE 0 END +  -- Medium significance
         CASE WHEN Parental_Death_in_Childhood = 1 THEN 3 ELSE 0 END +  -- High significance
         CASE WHEN Parental_Substance_Abuse = 1 THEN 2 ELSE 0 END +     -- Medium significance
         CASE WHEN Parent_Criminal_Record = 1 THEN 1 ELSE 0 END +      -- Low significance
         CASE WHEN Family_Member_Incarcerated = 1 THEN 2 ELSE 0 END    -- Medium significance
        ) AS Family_Background_Score,
        
        -- Childhood Trauma and Abuse Score (Total points: 20)
        (CASE WHEN Childhood_Trauma = 1 THEN 4 ELSE 0 END +            -- High significance
         CASE WHEN Physically_Abused = 1 THEN 4 ELSE 0 END +           -- High significance
         CASE WHEN Sexually_Abused = 1 THEN 5 ELSE 0 END +             -- Very high significance
         CASE WHEN Emotionally_Abused = 1 THEN 3 ELSE 0 END +          -- Medium significance
         CASE WHEN Neglected = 1 THEN 4 ELSE 0 END                     -- High significance
        ) AS Childhood_Trauma_Score,
        
        -- Psychological and Behavioral History Score (Total points: 40)
        (CASE WHEN Mental_Illness <> 'No evidence' THEN 6 ELSE 0 END +  -- Very high significance
         CASE WHEN Substance_Use IN ('Problem with alcohol', 'Other drugs') THEN 5 ELSE 0 END +  -- High significance
         CASE WHEN History_of_Physical_Altercations IS NOT NULL AND History_of_Physical_Altercations <> 'No evidence' THEN 6 ELSE 0 END +  -- Very high significance
         CASE WHEN History_of_Animal_Abuse = 1 THEN 3 ELSE 0 END +      -- Medium significance
         CASE WHEN History_of_Domestic_Abuse IS NOT NULL AND History_of_Domestic_Abuse <> 'No evidence' THEN 5 ELSE 0 END +    -- High significance
         CASE WHEN History_of_Sexual_Offenses = 1 THEN 6 ELSE 0 END +   -- Very high significance
         CASE WHEN Gang_Affiliation = 1 THEN 2 ELSE 0 END +             -- Low significance
         CASE WHEN Terror_Group_Affiliation = 1 THEN 3 ELSE 0 END +     -- Medium significance
         CASE WHEN Known_Hate_Group_or_Chat_Room_Affiliation_Code = 1 THEN 3 ELSE 0 END +  -- Medium significance
         CASE WHEN Adult_Trauma IS NOT NULL AND Adult_Trauma <> 'No evidence' THEN 5 ELSE 0 END  -- High significance
        ) AS Psychological_Behavioral_Score,
        
        -- Recent Stressors and Crisis Indicators Score (Total points: 30)
        (CASE WHEN Recent_or_Ongoing_Stressor IS NOT NULL AND Recent_or_Ongoing_Stressor <> 'No evidence' THEN 4 ELSE 0 END +  -- High significance
         CASE WHEN Signs_of_Being_in_Crisis = 1 THEN 5 ELSE 0 END +    -- Very high significance
         CASE WHEN Crisis_Six_Months_or_Less = 1 THEN 4 ELSE 0 END +   -- High significance
         CASE WHEN Paranoia = 1 THEN 3 ELSE 0 END +                    -- Medium significance
         CASE WHEN Rapid_Mood_Swings = 1 THEN 3 ELSE 0 END +           -- Medium significance
         CASE WHEN Isolation = 1 THEN 2 ELSE 0 END +                   -- Low significance
         CASE WHEN Abusive_Behavior = 1 THEN 4 ELSE 0 END +            -- High significance
         CASE WHEN Suicidality IS NOT NULL AND Suicidality <> 'No evidence' THEN 5 ELSE 0 END  -- Very high significance
        ) AS Recent_Stressor_Score
    FROM mass_shooter
),
Overall_Scoring AS (
    SELECT
        case_no,
        Family_Background_Score,
        Childhood_Trauma_Score,
        Psychological_Behavioral_Score,
        Recent_Stressor_Score,
        (Family_Background_Score + 
         Childhood_Trauma_Score + 
         Psychological_Behavioral_Score + 
         Recent_Stressor_Score) AS Overall_Composite_Risk_Score
    FROM Scoring
)
SELECT
    'Family Background' AS Category,
    AVG(Family_Background_Score) AS Avg_Score,
    AVG(Family_Background_Score * 1.0 / Overall_Composite_Risk_Score) * 100 AS Percent_Contribution
FROM Overall_Scoring
UNION ALL
SELECT
    'Childhood Trauma and Abuse' AS Category,
    AVG(Childhood_Trauma_Score) AS Avg_Score,
    AVG(Childhood_Trauma_Score * 1.0 / Overall_Composite_Risk_Score) * 100 AS Percent_Contribution
FROM Overall_Scoring
UNION ALL
SELECT
    'Psychological and Behavioral History' AS Category,
    AVG(Psychological_Behavioral_Score) AS Avg_Score,
    AVG(Psychological_Behavioral_Score * 1.0 / Overall_Composite_Risk_Score) * 100 AS Percent_Contribution
FROM Overall_Scoring
UNION ALL
SELECT
    'Recent Stressors and Crisis Indicators' AS Category,
    AVG(Recent_Stressor_Score) AS Avg_Score,
    AVG(Recent_Stressor_Score * 1.0 / Overall_Composite_Risk_Score) * 100 AS Percent_Contribution
FROM Overall_Scoring
ORDER BY Percent_Contribution DESC;
    
-- Firearm Acquisition Risk Score: What percentage of firearms were obtained illegally vs. legally?
SELECT
    ROUND(
        (SUM(CASE WHEN Illegal_Purchase = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*)),
        2
    ) AS Percentage_Illegally_Obtained,
    ROUND(
        (SUM(CASE WHEN Legal_Purchase = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*)),
        2
    ) AS Percentage_Legally_Obtained
FROM
    firearms_used;

-- Motive Risk Score: What does it change over the decades?
SELECT 
  CONCAT(decade_group, 's') AS decade,
  COUNT(*) AS total_cases,
  ROUND(100.0 * SUM(hate_motive) / COUNT(*), 1) AS hate_pct,
  ROUND(100.0 * SUM(grievance_motive) / COUNT(*), 1) AS grievance_pct,
  ROUND(100.0 * SUM(fame_motive) / COUNT(*), 1) AS fame_pct,
  ROUND(100.0 * SUM(economic_legal_motive) / COUNT(*), 1) AS economic_legal_pct,
  ROUND(100.0 * SUM(other_motive) / COUNT(*), 1) AS other_pct
FROM (
  SELECT 
    FLOOR(YEAR(date_formatted) / 10) * 10 AS decade_group,
    (Motive__Racism_Xenophobia_Code = 1 OR Motive__Religious_Hate_Code = 1) AS hate_motive,
    (Motive__Employment_Issue = 1 OR Motive__Relationship_Issue = 1) AS grievance_motive,
    (Motive__Fame_Seeking = 1) AS fame_motive,
    (Motive__Economic_Issue = 1 OR Motive__Legal_Issue = 1) AS economic_legal_motive,
    (Motive__Other_Code = 1) AS other_motive
  FROM mass_shooter
) AS derived_table
GROUP BY decade_group
ORDER BY decade_group;

____________________________________________________________________________________________________________________________________________________________________

-- Intervention Opportunity Rate: What percentage of mass shooters had missed intervention opportunities?
SELECT
    ROUND(
        (SUM(CASE WHEN (Known_to_Police_or_FBI = 'Yes' OR 
                        Prior_Hospitalization = 'Yes' OR 
                        Prior_Counseling = 'Yes' OR 
                        Psychiatric_Medication = 'Yes') AND 
                       Number_Killed > 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)),
        2
    ) AS Percentage_With_Missed_Intervention
FROM
    mass_shooter;

-- Creating Victim Impact Severity Scoree (VISS)
WITH Victim_Impact AS (
    SELECT 
        v.Case__,
        -- Fatalities: 5 points per death (from mass_shooter table)
        MAX(m.Number_Killed) * 5 AS Fatalities_Score,
        
        -- Injuries: 2 points per victim (count victim records)
        COUNT(*) * 2 AS Injuries_Score,
        
        -- Years Lost: Sum all years and divide by 10
        SUM(v.Years_Lost)/10 AS Years_Lost_Score
    FROM Victims v
    JOIN mass_shooter m ON v.Case__ = m.Case_No
    GROUP BY v.Case__
)
SELECT 
    Case__,
    Fatalities_Score,
    Injuries_Score,
    Years_Lost_Score,
    (Fatalities_Score + Injuries_Score + Years_Lost_Score) AS Victim_Impact_Severity_Score,
    -- Interpretation tier (optional)
    CASE 
        WHEN (Fatalities_Score + Injuries_Score + Years_Lost_Score) >= 50 THEN 'Mass Casualty Event'
        WHEN (Fatalities_Score + Injuries_Score + Years_Lost_Score) BETWEEN 30 AND 49 THEN 'Severe Impact'
        WHEN (Fatalities_Score + Injuries_Score + Years_Lost_Score) BETWEEN 15 AND 29 THEN 'Significant Event'
        ELSE 'Lower Impact Event'
    END AS Severity_Category
FROM Victim_Impact
ORDER BY Victim_Impact_Severity_Score DESC;

-- Victim Impact Severity Score: What are the top 10 incidents by total years lost?
SELECT
    Case__,
    Full_Date,
    SUM(Years_Lost) AS Total_Years_Lost
FROM
    victims
GROUP BY
    Case__,
    Full_Date
ORDER BY
    Total_Years_Lost DESC
LIMIT 10;

--------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Insights 1

WITH Scoring AS (
    SELECT 
        mass_shooter.case_no,
        -- Family Background (10 points total)
        (CASE WHEN Parental_Divorce_Separation = 1 THEN 2 ELSE 0 END +
         CASE WHEN Parental_Death_in_Childhood = 1 THEN 3 ELSE 0 END +
         CASE WHEN Parental_Substance_Abuse = 1 THEN 2 ELSE 0 END +
         CASE WHEN Parent_Criminal_Record = 1 THEN 1 ELSE 0 END +
         CASE WHEN Family_Member_Incarcerated = 1 THEN 2 ELSE 0 END) AS Family_Background_Score,
        
        -- Childhood Trauma (20 points total)
        (CASE WHEN Childhood_Trauma = 1 THEN 4 ELSE 0 END +
         CASE WHEN Physically_Abused = 1 THEN 4 ELSE 0 END +
         CASE WHEN Sexually_Abused = 1 THEN 5 ELSE 0 END +
         CASE WHEN Emotionally_Abused = 1 THEN 3 ELSE 0 END +
         CASE WHEN Neglected = 1 THEN 2 ELSE 0 END +
         CASE WHEN Bullied = 1 THEN 2 ELSE 0 END) AS Childhood_Trauma_Score,
        
        -- Psychological History (40 points total)
        (CASE WHEN Mental_Illness <> 'No evidence' THEN 6 ELSE 0 END +
         CASE WHEN Substance_Use IN ('Problem with alcohol', 'Other drugs') THEN 5 ELSE 0 END +
         CASE WHEN History_of_Physical_Altercations IS NOT NULL AND History_of_Physical_Altercations <> 'No evidence' THEN 6 ELSE 0 END +
         CASE WHEN History_of_Animal_Abuse = 1 THEN 3 ELSE 0 END +
         CASE WHEN History_of_Domestic_Abuse IS NOT NULL AND History_of_Domestic_Abuse <> 'No evidence' THEN 5 ELSE 0 END +
         CASE WHEN History_of_Sexual_Offenses = 1 THEN 6 ELSE 0 END +
         CASE WHEN Gang_Affiliation = 1 THEN 2 ELSE 0 END +
         CASE WHEN Terror_Group_Affiliation = 1 THEN 3 ELSE 0 END +
         CASE WHEN Known_Hate_Group_or_Chat_Room_Affiliation_Code = 1 THEN 3 ELSE 0 END +
         CASE WHEN Adult_Trauma IS NOT NULL AND Adult_Trauma <> 'No evidence' THEN 5 ELSE 0 END) AS Psychological_Behavioral_Score,
        
        -- Recent Stressors (30 points total)
        (CASE WHEN Recent_or_Ongoing_Stressor IS NOT NULL AND Recent_or_Ongoing_Stressor <> 'No evidence' THEN 4 ELSE 0 END +
         CASE WHEN Signs_of_Being_in_Crisis = 1 THEN 5 ELSE 0 END +
         CASE WHEN Crisis_Six_Months_or_Less = 1 THEN 4 ELSE 0 END +
         CASE WHEN Paranoia = 1 THEN 3 ELSE 0 END +
         CASE WHEN Rapid_Mood_Swings = 1 THEN 3 ELSE 0 END +
         CASE WHEN Isolation = 1 THEN 2 ELSE 0 END +
         CASE WHEN Abusive_Behavior = 1 THEN 4 ELSE 0 END +
         CASE WHEN Suicidality IS NOT NULL AND Suicidality <> 'No evidence' THEN 5 ELSE 0 END) AS Recent_Stressor_Score,
        
        -- Original columns needed for analysis
        Mental_Illness,
        Substance_Use,
        History_of_Physical_Altercations,
        Signs_of_Being_in_Crisis,
        Crisis_Six_Months_or_Less,
        Recent_or_Ongoing_Stressor,
        Childhood_Trauma,
        Physically_Abused,
        Sexually_Abused,
        Parental_Substance_Abuse,
        Parent_Criminal_Record,
        Full_Date
    FROM mass_shooter
),
CompositeScoring AS (
    SELECT
        case_no,
        Family_Background_Score,
        Childhood_Trauma_Score,
        Psychological_Behavioral_Score,
        Recent_Stressor_Score,
        (Family_Background_Score + 
         Childhood_Trauma_Score + 
         Psychological_Behavioral_Score + 
         Recent_Stressor_Score) AS Overall_Composite_Risk_Score,
        CASE
            WHEN (Family_Background_Score + Childhood_Trauma_Score + Psychological_Behavioral_Score + Recent_Stressor_Score) >= 61 THEN 'Extreme Risk'
            WHEN (Family_Background_Score + Childhood_Trauma_Score + Psychological_Behavioral_Score + Recent_Stressor_Score) BETWEEN 41 AND 60 THEN 'High Risk'
            WHEN (Family_Background_Score + Childhood_Trauma_Score + Psychological_Behavioral_Score + Recent_Stressor_Score) BETWEEN 15 AND 40 THEN 'Moderate Risk'
            ELSE 'Lower Risk'
        END AS Risk_Category,
        -- Original columns
        Mental_Illness,
        Substance_Use,
        History_of_Physical_Altercations,
        Signs_of_Being_in_Crisis,
        Crisis_Six_Months_or_Less,
        Recent_or_Ongoing_Stressor,
        Childhood_Trauma,
        Physically_Abused,
        Sexually_Abused,
        Parental_Substance_Abuse,
        Parent_Criminal_Record,
        Full_Date,
        EXTRACT(YEAR FROM Full_Date) AS year
    FROM Scoring
),
RiskFactorAnalysis AS (
    SELECT
        Risk_Category,
        COUNT(*) AS case_count,
        -- Psychological Factors
        ROUND(AVG(CASE WHEN Mental_Illness <> 'No evidence' THEN 1.0 ELSE 0 END)*100, 1) AS pct_mental_illness,
        ROUND(AVG(CASE WHEN Substance_Use IN ('Problem with alcohol', 'Other drugs') THEN 1.0 ELSE 0 END)*100, 1) AS pct_substance_abuse,
        ROUND(AVG(CASE WHEN History_of_Physical_Altercations IS NOT NULL 
                AND History_of_Physical_Altercations <> 'No evidence' THEN 1.0 ELSE 0 END)*100, 1) AS pct_violence_history,
        
        -- Recent Stressors
        ROUND(AVG(CASE WHEN Signs_of_Being_in_Crisis = 1 THEN 1.0 ELSE 0 END)*100, 1) AS pct_crisis_signs,
        ROUND(AVG(CASE WHEN Crisis_Six_Months_or_Less = 1 THEN 1.0 ELSE 0 END)*100, 1) AS pct_recent_crisis,
        ROUND(AVG(CASE WHEN Recent_or_Ongoing_Stressor IS NOT NULL 
                AND Recent_or_Ongoing_Stressor <> 'No evidence' THEN 1.0 ELSE 0 END)*100, 1) AS pct_recent_stressors,
        
        -- Childhood Trauma
        ROUND(AVG(CASE WHEN Childhood_Trauma = 1 OR Physically_Abused = 1 OR Sexually_Abused = 1 THEN 1.0 ELSE 0 END)*100, 1) AS pct_childhood_trauma,
        
        -- Family Background
        ROUND(AVG(CASE WHEN Parental_Substance_Abuse = 1 THEN 1.0 ELSE 0 END)*100, 1) AS pct_parent_substance_abuse,
        ROUND(AVG(CASE WHEN Parent_Criminal_Record = 1 THEN 1.0 ELSE 0 END)*100, 1) AS pct_parent_criminal_record,
        
        -- Average scores
        ROUND(AVG(Psychological_Behavioral_Score), 1) AS avg_psychological_score,
        ROUND(AVG(Recent_Stressor_Score), 1) AS avg_stressor_score,
        ROUND(AVG(Childhood_Trauma_Score), 1) AS avg_trauma_score,
        ROUND(AVG(Family_Background_Score), 1) AS avg_family_score,
        
        -- Time period breakdown
        ROUND(AVG(CASE WHEN year >= 2010 THEN 1.0 ELSE 0 END)*100, 1) AS pct_post_2010
    FROM CompositeScoring
    GROUP BY Risk_Category
)

SELECT 
    Risk_Category,
    case_count,
    pct_mental_illness,
    pct_substance_abuse,
    pct_violence_history,
    pct_crisis_signs,
    pct_recent_crisis,
    pct_recent_stressors,
    pct_childhood_trauma,
    pct_parent_substance_abuse,
    pct_parent_criminal_record,
    avg_psychological_score,
    avg_stressor_score,
    avg_trauma_score,
    avg_family_score,
    ROUND(avg_psychological_score/40*100, 1) AS psychological_score_pct,
    ROUND(avg_stressor_score/30*100, 1) AS stressor_score_pct,
    ROUND(avg_trauma_score/20*100, 1) AS trauma_score_pct,
    ROUND(avg_family_score/10*100, 1) AS family_score_pct,
    pct_post_2010
FROM RiskFactorAnalysis
ORDER BY 
    CASE Risk_Category
        WHEN 'Extreme Risk' THEN 4
        WHEN 'High Risk' THEN 3
        WHEN 'Moderate Risk' THEN 2
        ELSE 1
    END DESC;
    
    
-- Most common missed intervention points in severe cases

SELECT 
    'Prior System Contact' AS Category,
    'Known to Police/FBI' AS Factor,
    COUNT(*) AS Count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM Mass_Shooter WHERE 
        (CASE WHEN Known_to_Police_or_FBI = 1 THEN 2 ELSE 0 END + 
         CASE WHEN Criminal_Record = 1 THEN 3 ELSE 0 END + 
         CASE WHEN Prior_Hospitalization = 1 THEN 2 ELSE 0 END + 
         CASE WHEN Suicidality IS NOT NULL AND Suicidality <> 'No evidence' THEN 2 ELSE 0 END + 
         CASE WHEN Prior_Counseling = 1 THEN 1 ELSE 0 END + 
         CASE WHEN Psychiatric_Medication IS NOT NULL THEN 2 ELSE 0 END + 
         CASE WHEN History_of_Physical_Altercations IS NOT NULL AND History_of_Physical_Altercations <> 'No evidence' THEN 1 ELSE 0 END + 
         CASE WHEN History_of_Domestic_Abuse IS NOT NULL AND History_of_Domestic_Abuse <> 'No evidence' THEN 2 ELSE 0 END + 
         CASE WHEN Gang_Affiliation = 1 THEN 2 ELSE 0 END) +
        (CASE WHEN Signs_of_Being_in_Crisis = 1 THEN 2 ELSE 0 END + 
         CASE WHEN Crisis_Six_Months_or_Less = 1 THEN 1 ELSE 0 END + 
         CASE WHEN Paranoia = 1 THEN 1 ELSE 0 END + 
         CASE WHEN Rapid_Mood_Swings = 1 THEN 1 ELSE 0 END + 
         CASE WHEN Isolation = 1 THEN 1 ELSE 0 END + 
         CASE WHEN Abusive_Behavior = 1 THEN 1 ELSE 0 END + 
         CASE WHEN Recent_or_Ongoing_Stressor IS NOT NULL AND Recent_or_Ongoing_Stressor <> 'No evidence' THEN 1 ELSE 0 END) +
        (CASE WHEN Leakage = 1 THEN 3 + 
              CASE WHEN Leakage_Who LIKE '%Police%' OR Leakage_Who LIKE '%Mental health%' THEN 2 
                   WHEN Leakage_Who IS NOT NULL THEN 1 ELSE 0 END + 
              CASE WHEN Leakage_How IN ('Direct Threat', 'Manifesto') THEN 2 
                   WHEN Leakage_How IS NOT NULL THEN 1 ELSE 0 END 
         ELSE 0 END) >= 12), 1) AS Percentage
FROM Mass_Shooter
WHERE Known_to_Police_or_FBI = 1 AND 
    (CASE WHEN Known_to_Police_or_FBI = 1 THEN 2 ELSE 0 END + 
     CASE WHEN Criminal_Record = 1 THEN 3 ELSE 0 END + 
     CASE WHEN Prior_Hospitalization = 1 THEN 2 ELSE 0 END + 
     CASE WHEN Suicidality IS NOT NULL AND Suicidality <> 'No evidence' THEN 2 ELSE 0 END + 
     CASE WHEN Prior_Counseling = 1 THEN 1 ELSE 0 END + 
     CASE WHEN Psychiatric_Medication IS NOT NULL THEN 2 ELSE 0 END + 
     CASE WHEN History_of_Physical_Altercations IS NOT NULL AND History_of_Physical_Altercations <> 'No evidence' THEN 1 ELSE 0 END + 
     CASE WHEN History_of_Domestic_Abuse IS NOT NULL AND History_of_Domestic_Abuse <> 'No evidence' THEN 2 ELSE 0 END + 
     CASE WHEN Gang_Affiliation = 1 THEN 2 ELSE 0 END) +
    (CASE WHEN Signs_of_Being_in_Crisis = 1 THEN 2 ELSE 0 END + 
     CASE WHEN Crisis_Six_Months_or_Less = 1 THEN 1 ELSE 0 END + 
     CASE WHEN Paranoia = 1 THEN 1 ELSE 0 END + 
     CASE WHEN Rapid_Mood_Swings = 1 THEN 1 ELSE 0 END + 
     CASE WHEN Isolation = 1 THEN 1 ELSE 0 END + 
     CASE WHEN Abusive_Behavior = 1 THEN 1 ELSE 0 END + 
     CASE WHEN Recent_or_Ongoing_Stressor IS NOT NULL AND Recent_or_Ongoing_Stressor <> 'No evidence' THEN 1 ELSE 0 END) +
    (CASE WHEN Leakage = 1 THEN 3 + 
          CASE WHEN Leakage_Who LIKE '%Police%' OR Leakage_Who LIKE '%Mental health%' THEN 2 
               WHEN Leakage_Who IS NOT NULL THEN 1 ELSE 0 END + 
          CASE WHEN Leakage_How IN ('Direct Threat', 'Manifesto') THEN 2 
               WHEN Leakage_How IS NOT NULL THEN 1 ELSE 0 END 
     ELSE 0 END) >= 12

UNION ALL

SELECT 
    'Prior System Contact',
    'Criminal Record',
    COUNT(*),
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM Mass_Shooter WHERE 
        (CASE WHEN Known_to_Police_or_FBI = 1 THEN 2 ELSE 0 END + 
         CASE WHEN Criminal_Record = 1 THEN 3 ELSE 0 END + 
         CASE WHEN Prior_Hospitalization = 1 THEN 2 ELSE 0 END + 
         CASE WHEN Suicidality IS NOT NULL AND Suicidality <> 'No evidence' THEN 2 ELSE 0 END + 
         CASE WHEN Prior_Counseling = 1 THEN 1 ELSE 0 END + 
         CASE WHEN Psychiatric_Medication IS NOT NULL THEN 2 ELSE 0 END + 
         CASE WHEN History_of_Physical_Altercations IS NOT NULL AND History_of_Physical_Altercations <> 'No evidence' THEN 1 ELSE 0 END + 
         CASE WHEN History_of_Domestic_Abuse IS NOT NULL AND History_of_Domestic_Abuse <> 'No evidence' THEN 2 ELSE 0 END + 
         CASE WHEN Gang_Affiliation = 1 THEN 2 ELSE 0 END) +
        (CASE WHEN Signs_of_Being_in_Crisis = 1 THEN 2 ELSE 0 END + 
         CASE WHEN Crisis_Six_Months_or_Less = 1 THEN 1 ELSE 0 END + 
         CASE WHEN Paranoia = 1 THEN 1 ELSE 0 END + 
         CASE WHEN Rapid_Mood_Swings = 1 THEN 1 ELSE 0 END + 
         CASE WHEN Isolation = 1 THEN 1 ELSE 0 END + 
         CASE WHEN Abusive_Behavior = 1 THEN 1 ELSE 0 END + 
         CASE WHEN Recent_or_Ongoing_Stressor IS NOT NULL AND Recent_or_Ongoing_Stressor <> 'No evidence' THEN 1 ELSE 0 END) +
        (CASE WHEN Leakage = 1 THEN 3 + 
              CASE WHEN Leakage_Who LIKE '%Police%' OR Leakage_Who LIKE '%Mental health%' THEN 2 
                   WHEN Leakage_Who IS NOT NULL THEN 1 ELSE 0 END + 
              CASE WHEN Leakage_How IN ('Direct Threat', 'Manifesto') THEN 2 
                   WHEN Leakage_How IS NOT NULL THEN 1 ELSE 0 END 
         ELSE 0 END) >= 12), 1)
FROM Mass_Shooter
WHERE Criminal_Record = 1 AND 
    (CASE WHEN Known_to_Police_or_FBI = 1 THEN 2 ELSE 0 END + 
     CASE WHEN Criminal_Record = 1 THEN 3 ELSE 0 END + 
     CASE WHEN Prior_Hospitalization = 1 THEN 2 ELSE 0 END + 
     CASE WHEN Suicidality IS NOT NULL AND Suicidality <> 'No evidence' THEN 2 ELSE 0 END + 
     CASE WHEN Prior_Counseling = 1 THEN 1 ELSE 0 END + 
     CASE WHEN Psychiatric_Medication IS NOT NULL THEN 2 ELSE 0 END + 
     CASE WHEN History_of_Physical_Altercations IS NOT NULL AND History_of_Physical_Altercations <> 'No evidence' THEN 1 ELSE 0 END + 
     CASE WHEN History_of_Domestic_Abuse IS NOT NULL AND History_of_Domestic_Abuse <> 'No evidence' THEN 2 ELSE 0 END + 
     CASE WHEN Gang_Affiliation = 1 THEN 2 ELSE 0 END) +
    (CASE WHEN Signs_of_Being_in_Crisis = 1 THEN 2 ELSE 0 END + 
     CASE WHEN Crisis_Six_Months_or_Less = 1 THEN 1 ELSE 0 END + 
     CASE WHEN Paranoia = 1 THEN 1 ELSE 0 END + 
     CASE WHEN Rapid_Mood_Swings = 1 THEN 1 ELSE 0 END + 
     CASE WHEN Isolation = 1 THEN 1 ELSE 0 END + 
     CASE WHEN Abusive_Behavior = 1 THEN 1 ELSE 0 END + 
     CASE WHEN Recent_or_Ongoing_Stressor IS NOT NULL AND Recent_or_Ongoing_Stressor <> 'No evidence' THEN 1 ELSE 0 END) +
    (CASE WHEN Leakage = 1 THEN 3 + 
          CASE WHEN Leakage_Who LIKE '%Police%' OR Leakage_Who LIKE '%Mental health%' THEN 2 
               WHEN Leakage_Who IS NOT NULL THEN 1 ELSE 0 END + 
          CASE WHEN Leakage_How IN ('Direct Threat', 'Manifesto') THEN 2 
               WHEN Leakage_How IS NOT NULL THEN 1 ELSE 0 END 
     ELSE 0 END) >= 12

UNION ALL

SELECT 
    'Prior System Contact',
    'Prior Mental Health Hospitalization',
    COUNT(*),
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM Mass_Shooter WHERE 
        (CASE WHEN Known_to_Police_or_FBI = 1 THEN 2 ELSE 0 END + 
         CASE WHEN Criminal_Record = 1 THEN 3 ELSE 0 END + 
         CASE WHEN Prior_Hospitalization = 1 THEN 2 ELSE 0 END + 
         CASE WHEN Suicidality IS NOT NULL AND Suicidality <> 'No evidence' THEN 2 ELSE 0 END + 
         CASE WHEN Prior_Counseling = 1 THEN 1 ELSE 0 END + 
         CASE WHEN Psychiatric_Medication IS NOT NULL THEN 2 ELSE 0 END + 
         CASE WHEN History_of_Physical_Altercations IS NOT NULL AND History_of_Physical_Altercations <> 'No evidence' THEN 1 ELSE 0 END + 
         CASE WHEN History_of_Domestic_Abuse IS NOT NULL AND History_of_Domestic_Abuse <> 'No evidence' THEN 2 ELSE 0 END + 
         CASE WHEN Gang_Affiliation = 1 THEN 2 ELSE 0 END) +
        (CASE WHEN Signs_of_Being_in_Crisis = 1 THEN 2 ELSE 0 END + 
         CASE WHEN Crisis_Six_Months_or_Less = 1 THEN 1 ELSE 0 END + 
         CASE WHEN Paranoia = 1 THEN 1 ELSE 0 END + 
         CASE WHEN Rapid_Mood_Swings = 1 THEN 1 ELSE 0 END + 
         CASE WHEN Isolation = 1 THEN 1 ELSE 0 END + 
         CASE WHEN Abusive_Behavior = 1 THEN 1 ELSE 0 END + 
         CASE WHEN Recent_or_Ongoing_Stressor IS NOT NULL AND Recent_or_Ongoing_Stressor <> 'No evidence' THEN 1 ELSE 0 END) +
        (CASE WHEN Leakage = 1 THEN 3 + 
              CASE WHEN Leakage_Who LIKE '%Police%' OR Leakage_Who LIKE '%Mental health%' THEN 2 
                   WHEN Leakage_Who IS NOT NULL THEN 1 ELSE 0 END + 
              CASE WHEN Leakage_How IN ('Direct Threat', 'Manifesto') THEN 2 
                   WHEN Leakage_How IS NOT NULL THEN 1 ELSE 0 END 
         ELSE 0 END) >= 12), 1)
FROM Mass_Shooter
WHERE Prior_Hospitalization = 1 AND 
    (CASE WHEN Known_to_Police_or_FBI = 1 THEN 2 ELSE 0 END + 
     CASE WHEN Criminal_Record = 1 THEN 3 ELSE 0 END + 
     CASE WHEN Prior_Hospitalization = 1 THEN 2 ELSE 0 END + 
     CASE WHEN Suicidality IS NOT NULL AND Suicidality <> 'No evidence' THEN 2 ELSE 0 END + 
     CASE WHEN Prior_Counseling = 1 THEN 1 ELSE 0 END + 
     CASE WHEN Psychiatric_Medication IS NOT NULL THEN 2 ELSE 0 END + 
     CASE WHEN History_of_Physical_Altercations IS NOT NULL AND History_of_Physical_Altercations <> 'No evidence' THEN 1 ELSE 0 END + 
     CASE WHEN History_of_Domestic_Abuse IS NOT NULL AND History_of_Domestic_Abuse <> 'No evidence' THEN 2 ELSE 0 END + 
     CASE WHEN Gang_Affiliation = 1 THEN 2 ELSE 0 END) +
    (CASE WHEN Signs_of_Being_in_Crisis = 1 THEN 2 ELSE 0 END + 
     CASE WHEN Crisis_Six_Months_or_Less = 1 THEN 1 ELSE 0 END + 
     CASE WHEN Paranoia = 1 THEN 1 ELSE 0 END + 
     CASE WHEN Rapid_Mood_Swings = 1 THEN 1 ELSE 0 END + 
     CASE WHEN Isolation = 1 THEN 1 ELSE 0 END + 
     CASE WHEN Abusive_Behavior = 1 THEN 1 ELSE 0 END + 
     CASE WHEN Recent_or_Ongoing_Stressor IS NOT NULL AND Recent_or_Ongoing_Stressor <> 'No evidence' THEN 1 ELSE 0 END) +
    (CASE WHEN Leakage = 1 THEN 3 + 
          CASE WHEN Leakage_Who LIKE '%Police%' OR Leakage_Who LIKE '%Mental health%' THEN 2 
               WHEN Leakage_Who IS NOT NULL THEN 1 ELSE 0 END + 
          CASE WHEN Leakage_How IN ('Direct Threat', 'Manifesto') THEN 2 
               WHEN Leakage_How IS NOT NULL THEN 1 ELSE 0 END 
     ELSE 0 END) >= 12

UNION ALL

SELECT 
    'Signs of Crisis',
    'Signs of Being in Crisis',
    COUNT(*),
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM Mass_Shooter WHERE 
        (CASE WHEN Known_to_Police_or_FBI = 1 THEN 2 ELSE 0 END + 
         CASE WHEN Criminal_Record = 1 THEN 3 ELSE 0 END + 
         CASE WHEN Prior_Hospitalization = 1 THEN 2 ELSE 0 END + 
         CASE WHEN Suicidality IS NOT NULL AND Suicidality <> 'No evidence' THEN 2 ELSE 0 END + 
         CASE WHEN Prior_Counseling = 1 THEN 1 ELSE 0 END + 
         CASE WHEN Psychiatric_Medication IS NOT NULL THEN 2 ELSE 0 END + 
         CASE WHEN History_of_Physical_Altercations IS NOT NULL AND History_of_Physical_Altercations <> 'No evidence' THEN 1 ELSE 0 END + 
         CASE WHEN History_of_Domestic_Abuse IS NOT NULL AND History_of_Domestic_Abuse <> 'No evidence' THEN 2 ELSE 0 END + 
         CASE WHEN Gang_Affiliation = 1 THEN 2 ELSE 0 END) +
        (CASE WHEN Signs_of_Being_in_Crisis = 1 THEN 2 ELSE 0 END + 
         CASE WHEN Crisis_Six_Months_or_Less = 1 THEN 1 ELSE 0 END + 
         CASE WHEN Paranoia = 1 THEN 1 ELSE 0 END + 
         CASE WHEN Rapid_Mood_Swings = 1 THEN 1 ELSE 0 END + 
         CASE WHEN Isolation = 1 THEN 1 ELSE 0 END + 
         CASE WHEN Abusive_Behavior = 1 THEN 1 ELSE 0 END + 
         CASE WHEN Recent_or_Ongoing_Stressor IS NOT NULL AND Recent_or_Ongoing_Stressor <> 'No evidence' THEN 1 ELSE 0 END) +
        (CASE WHEN Leakage = 1 THEN 3 + 
              CASE WHEN Leakage_Who LIKE '%Police%' OR Leakage_Who LIKE '%Mental health%' THEN 2 
                   WHEN Leakage_Who IS NOT NULL THEN 1 ELSE 0 END + 
              CASE WHEN Leakage_How IN ('Direct Threat', 'Manifesto') THEN 2 
                   WHEN Leakage_How IS NOT NULL THEN 1 ELSE 0 END 
         ELSE 0 END) >= 12), 1)
FROM Mass_Shooter
WHERE Signs_of_Being_in_Crisis = 1 AND 
    (CASE WHEN Known_to_Police_or_FBI = 1 THEN 2 ELSE 0 END + 
     CASE WHEN Criminal_Record = 1 THEN 3 ELSE 0 END + 
     CASE WHEN Prior_Hospitalization = 1 THEN 2 ELSE 0 END + 
     CASE WHEN Suicidality IS NOT NULL AND Suicidality <> 'No evidence' THEN 2 ELSE 0 END + 
     CASE WHEN Prior_Counseling = 1 THEN 1 ELSE 0 END + 
     CASE WHEN Psychiatric_Medication IS NOT NULL THEN 2 ELSE 0 END + 
     CASE WHEN History_of_Physical_Altercations IS NOT NULL AND History_of_Physical_Altercations <> 'No evidence' THEN 1 ELSE 0 END + 
     CASE WHEN History_of_Domestic_Abuse IS NOT NULL AND History_of_Domestic_Abuse <> 'No evidence' THEN 2 ELSE 0 END + 
     CASE WHEN Gang_Affiliation = 1 THEN 2 ELSE 0 END) +
    (CASE WHEN Signs_of_Being_in_Crisis = 1 THEN 2 ELSE 0 END + 
     CASE WHEN Crisis_Six_Months_or_Less = 1 THEN 1 ELSE 0 END + 
     CASE WHEN Paranoia = 1 THEN 1 ELSE 0 END + 
     CASE WHEN Rapid_Mood_Swings = 1 THEN 1 ELSE 0 END + 
     CASE WHEN Isolation = 1 THEN 1 ELSE 0 END + 
     CASE WHEN Abusive_Behavior = 1 THEN 1 ELSE 0 END + 
     CASE WHEN Recent_or_Ongoing_Stressor IS NOT NULL AND Recent_or_Ongoing_Stressor <> 'No evidence' THEN 1 ELSE 0 END) +
    (CASE WHEN Leakage = 1 THEN 3 + 
          CASE WHEN Leakage_Who LIKE '%Police%' OR Leakage_Who LIKE '%Mental health%' THEN 2 
               WHEN Leakage_Who IS NOT NULL THEN 1 ELSE 0 END + 
          CASE WHEN Leakage_How IN ('Direct Threat', 'Manifesto') THEN 2 
               WHEN Leakage_How IS NOT NULL THEN 1 ELSE 0 END 
     ELSE 0 END) >= 12

UNION ALL

SELECT 
    'Leakage',
    'Leakage to Authorities',
    COUNT(*),
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM Mass_Shooter WHERE 
        (CASE WHEN Known_to_Police_or_FBI = 1 THEN 2 ELSE 0 END + 
         CASE WHEN Criminal_Record = 1 THEN 3 ELSE 0 END + 
         CASE WHEN Prior_Hospitalization = 1 THEN 2 ELSE 0 END + 
         CASE WHEN Suicidality IS NOT NULL AND Suicidality <> 'No evidence' THEN 2 ELSE 0 END + 
         CASE WHEN Prior_Counseling = 1 THEN 1 ELSE 0 END + 
         CASE WHEN Psychiatric_Medication IS NOT NULL THEN 2 ELSE 0 END + 
         CASE WHEN History_of_Physical_Altercations IS NOT NULL AND History_of_Physical_Altercations <> 'No evidence' THEN 1 ELSE 0 END + 
         CASE WHEN History_of_Domestic_Abuse IS NOT NULL AND History_of_Domestic_Abuse <> 'No evidence' THEN 2 ELSE 0 END + 
         CASE WHEN Gang_Affiliation = 1 THEN 2 ELSE 0 END) +
        (CASE WHEN Signs_of_Being_in_Crisis = 1 THEN 2 ELSE 0 END + 
         CASE WHEN Crisis_Six_Months_or_Less = 1 THEN 1 ELSE 0 END + 
         CASE WHEN Paranoia = 1 THEN 1 ELSE 0 END + 
         CASE WHEN Rapid_Mood_Swings = 1 THEN 1 ELSE 0 END + 
         CASE WHEN Isolation = 1 THEN 1 ELSE 0 END + 
         CASE WHEN Abusive_Behavior = 1 THEN 1 ELSE 0 END + 
         CASE WHEN Recent_or_Ongoing_Stressor IS NOT NULL AND Recent_or_Ongoing_Stressor <> 'No evidence' THEN 1 ELSE 0 END) +
        (CASE WHEN Leakage = 1 THEN 3 + 
              CASE WHEN Leakage_Who LIKE '%Police%' OR Leakage_Who LIKE '%Mental health%' THEN 2 
                   WHEN Leakage_Who IS NOT NULL THEN 1 ELSE 0 END + 
              CASE WHEN Leakage_How IN ('Direct Threat', 'Manifesto') THEN 2 
                   WHEN Leakage_How IS NOT NULL THEN 1 ELSE 0 END 
         ELSE 0 END) >= 12), 1)
FROM Mass_Shooter
WHERE Leakage = 1 AND 
    (Leakage_Who LIKE '%Police%' OR Leakage_Who LIKE '%Mental health%') AND 
    (CASE WHEN Known_to_Police_or_FBI = 1 THEN 2 ELSE 0 END + 
     CASE WHEN Criminal_Record = 1 THEN 3 ELSE 0 END + 
     CASE WHEN Prior_Hospitalization = 1 THEN 2 ELSE 0 END + 
     CASE WHEN Suicidality IS NOT NULL AND Suicidality <> 'No evidence' THEN 2 ELSE 0 END + 
     CASE WHEN Prior_Counseling = 1 THEN 1 ELSE 0 END + 
     CASE WHEN Psychiatric_Medication IS NOT NULL THEN 2 ELSE 0 END + 
     CASE WHEN History_of_Physical_Altercations IS NOT NULL AND History_of_Physical_Altercations <> 'No evidence' THEN 1 ELSE 0 END + 
     CASE WHEN History_of_Domestic_Abuse IS NOT NULL AND History_of_Domestic_Abuse <> 'No evidence' THEN 2 ELSE 0 END + 
     CASE WHEN Gang_Affiliation = 1 THEN 2 ELSE 0 END) +
    (CASE WHEN Signs_of_Being_in_Crisis = 1 THEN 2 ELSE 0 END + 
     CASE WHEN Crisis_Six_Months_or_Less = 1 THEN 1 ELSE 0 END + 
     CASE WHEN Paranoia = 1 THEN 1 ELSE 0 END + 
     CASE WHEN Rapid_Mood_Swings = 1 THEN 1 ELSE 0 END + 
     CASE WHEN Isolation = 1 THEN 1 ELSE 0 END + 
     CASE WHEN Abusive_Behavior = 1 THEN 1 ELSE 0 END + 
     CASE WHEN Recent_or_Ongoing_Stressor IS NOT NULL AND Recent_or_Ongoing_Stressor <> 'No evidence' THEN 1 ELSE 0 END) +
    (CASE WHEN Leakage = 1 THEN 3 + 
          CASE WHEN Leakage_Who LIKE '%Police%' OR Leakage_Who LIKE '%Mental health%' THEN 2 
               WHEN Leakage_Who IS NOT NULL THEN 1 ELSE 0 END + 
          CASE WHEN Leakage_How IN ('Direct Threat', 'Manifesto') THEN 2 
               WHEN Leakage_How IS NOT NULL THEN 1 ELSE 0 END 
     ELSE 0 END) >= 12

ORDER BY Category, Percentage DESC;

