use medpractice;

#stored procedure
DELIMITER //
CREATE procedure physician_info (IN id VARCHAR(11))
BEGIN
	SELECT primary_specialty, experience_years
	FROM physicians P
	WHERE P.ssn = id;
END //
DELIMITER ;

#test
CALL physician_info('614-57-6885');

#trigger

DELIMITER //
CREATE TRIGGER adverse
AFTER INSERT ON prescriptions 
FOR EACH ROW 
BEGIN
    
	IF NEW.drug_name IN (
		SELECT N.drugs
		FROM (
			SELECT A1.drug_name2 as drugs
			FROM adverse_interactions A1 
			WHERE A1.drug_name1 IN (
				SELECT P.drug_name 
				FROM prescriptions P 
				WHERE P.patient_id = NEW.patient_ID
			) 
			UNION
			SELECT A2.drug_name1 as drugs
			FROM adverse_interactions A2 
			WHERE A2.drug_name2 IN (
				SELECT P.drug_name 
				FROM prescriptions P 
				WHERE P.patient_id = NEW.patient_ID
			)
		  ) N 
		) THEN
		
		INSERT INTO alerts (patient_id, physician_id, alert_date, drug1, drug2)
        SELECT NEW.patient_id, NEW.physician_id, NEW.date, O.drug, NEW.drug_name
        FROM  (
				SELECT P.drug_name as drug
				FROM prescriptions P 
				WHERE P.patient_id = NEW.patient_ID AND P.drug_name in 
					(SELECT A1.drug_name2 
					FROM adverse_interactions A1 
					WHERE A1.drug_name1=NEW.drug_name
					UNION
					SELECT A2.drug_name1
					FROM adverse_interactions A2 
					WHERE A2.drug_name2=NEW.drug_name) 
			    ) O;
END IF;
END;
//
DELIMITER ; 

#test
-- INSERT INTO prescriptions VALUES ('140','777-39-3296','718-27-0905','Avafoxin','2023-12-30','10');
-- INSERT INTO prescriptions VALUES ('141','777-39-3296','718-27-0905','Quixiposide','2023-12-31','10');

#q1 Find the physicians (ssn) who have most prescribed drugs which caused alerts
WITH alertcounts AS (
    SELECT physician_id, COUNT(*) as alert_count
    FROM alerts 
    GROUP BY physician_id
)
SELECT physician_id
FROM alertcounts
WHERE alert_count = (SELECT MAX(alert_count) FROM alertcounts);

#q2 Find the physicians (ssn) who have prescribed two drugs to the same patient which have adverse interactions
SELECT distinct P1.physician_id
FROM prescriptions P1, prescriptions P2
WHERE P1.physician_id=P2.physician_id AND P1.patient_id=P2.patient_id AND P2.drug_name in ((SELECT A.drug_name1
																					  FROM adverse_interactions A
																					  WHERE A.drug_name2=P1.drug_name)
                                                                                      UNION
                                                                                      (SELECT A.drug_name2
																					  FROM adverse_interactions A
																					  WHERE A.drug_name1=P1.drug_name));

#q3 Find the physicians who have prescribed most drugs supplied by company DRUGXO
WITH DRUGXO_counts AS (
    SELECT P.physician_id, COUNT(*) AS phys_count
    FROM prescriptions P
	JOIN (SELECT distinct C.drug_name
		  FROM contracts C 
	      JOIN companies COM on C.company_id = COM.id 
		  WHERE COM.name = 'DRUGXO') J on J.drug_name=P.drug_name
    GROUP BY P.physician_id
)
SELECT physician_id
FROM DRUGXO_counts
WHERE phys_count = (SELECT MAX(phys_count) FROM DRUGXO_counts);

#q4 For each drug supplied by company PHARMASEE display the price (per unit of quantity) charged by that company for that drug along with the average price charged for that drug (by companies, not pharmacies)
CREATE table drug_average
	SELECT drug_name, avg(price/quantity) as avg_price
	FROM contracts
	GROUP BY drug_name;
    
SELECT CON.drug_name, (CON.price/CON.quantity) as price_per_unit, D.avg_price as avg_price
FROM contracts CON
JOIN companies COM ON CON.company_id = COM.id
JOIN drug_average D on CON.drug_name=D.drug_name
WHERE COM.name = 'PHARMASEE';

#q5 For each drug and for each pharmacy, find the percentage of the markup (per unit of quantity) for that drug by that pharmacy
SELECT DP.drug_name, DP.ph_name as pharmacy, 100 * (((PP.cost / PP.quantity) - (C.price / C.quantity)) / (C.price / C.quantity)) AS percent_markup
FROM (SELECT P.id as ph_id, P.name as ph_name, D.id as drug_id, D.name as drug_name
	  FROM pharmacies P, drugs D) as DP
LEFT JOIN (SELECT Pr.drug_name, Pf.pharmacy_id, Pf.cost, Pr.quantity
		   FROM prescriptions Pr 
		   JOIN pharmacy_fills Pf on Pf.prescription_id=Pr.id) as PP on PP.pharmacy_id=DP.ph_id AND PP.drug_name=DP.drug_name
LEFT JOIN contracts C on C.drug_name=PP.drug_name AND C.pharmacy_id=PP.pharmacy_id;

#q6 For each drug, find the average time between when a patient was prescribed a drug and when the prescription was filled at a pharmacy
SELECT avg(DATEDIFF(P.date,Pr.date)) AS avg_days, D.name
FROM drugs D
LEFT JOIN prescriptions Pr on D.name=Pr.drug_name
LEFT JOIN pharmacy_fills P ON Pr.id=P.prescription_id
GROUP BY D.name;

#q7 For each pharmacy, find all the drugs that were prescribed to a patient and never filled at that pharmacy

CREATE TABLE cartesian
	SELECT Pr.drug_name, P.id as pharmacy_id
	FROM prescriptions Pr, pharmacies P;

SELECT pharmacy_id, drug_name
FROM cartesian C
WHERE (C.drug_name, C.pharmacy_id) NOT IN (
		SELECT P.drug_name, Pf.pharmacy_id
		FROM pharmacy_fills Pf
        JOIN prescriptions P on p.id=Pf.prescription_id
	)
GROUP BY pharmacy_id, drug_name
ORDER BY pharmacy_id;
