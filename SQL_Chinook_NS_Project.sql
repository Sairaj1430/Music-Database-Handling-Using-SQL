use chinook;
/* 1.	Does any table have missing values or duplicates? If yes, how would you handle it? */

SELECT * FROM album; -- album_id, title, artist_id
SELECT * FROM artist; -- artist_id, name
SELECT * FROM customer; -- customer_id, first_name, last_name, company, address, city, state, country, postal_code, phone, fax, email, support_rep_id
SELECT * FROM employee; -- employee_id, last_name, first_name, title, reports_to, birthdate, hire_date, address, city, state, country, postal_code, phone, fax, email
SELECT * FROM genre; -- genre_id, name
SELECT * FROM invoice; -- invoice_id, customer_id, invoice_date, billing_address, billing_city, billing_state, billing_country, billing_postal_code, total
SELECT * FROM invoice_line; -- invoice_line_id, invoice_id, track_id, unit_price, quantity
SELECT * FROM media_type; -- media_type_id, name
SELECT * FROM playlist; -- playlist_id, name
SELECT * FROM playlist_track; -- playlist_id, track_id
SELECT * FROM track; -- track_id, name, album_id, media_type_id, genre_id, composer, milliseconds, bytes, unit_price

UPDATE customer SET company = 'Unknown' WHERE company IS NULL; -- 49 row(s) affected
UPDATE customer SET state = 'None' WHERE state IS NULL; -- 29 row(s) affected
UPDATE customer SET phone = '+0 000 000 0000' WHERE phone IS NULL; -- 1 row(s) affected
UPDATE customer SET fax = '+0 000 000 0000' WHERE fax IS NULL; -- 47 row(s) affected
UPDATE track SET composer = 'Unknown' WHERE composer IS NULL; -- 978 row(s) affected


-- --------------------------------------------------------------------------------------------------------------------------------------------------

/* 2.	Find the top-selling tracks and top artist in the USA and identify their most famous genres. */ -- Count of genres

WITH topSellingTracknArtist AS (
	SELECT 
		t.name AS track_name,
        a.name AS artist_name,
        g.name AS genre_name,
        SUM(i.total) AS total_sales,
        COUNT(g.genre_id) AS genre_count,
        RANK() OVER(ORDER BY SUM(i.total) DESC) AS sales_rank
	FROM invoice i 
    JOIN invoice_line il ON i.invoice_id = il.invoice_id
    JOIN track t ON il.track_id = t.track_id
    JOIN album al ON t.album_id = al.album_id
    JOIN artist a ON al.artist_id = a.artist_id
    JOIN genre g ON t.genre_id = g.genre_id
    WHERE i.billing_country = 'USA'
	GROUP BY t.name,a.name,g.name
    
),

MaxGenreCount AS (
	SELECT MAX(c) AS famous_genre FROM ( SELECT COUNT(DISTINCT genre_id) AS c FROM track t ) sub
)

SELECT * FROM topSellingTracknArtist ORDER BY total_sales DESC;

-- --------------------------------------------------------------------------------------------------------------------------------------------------

/* 3.	What is the customer demographic breakdown (age, gender, location) of Chinook's customer base? */

SELECT 
	country,
	COALESCE(state,'None') AS state,
	city, 
	COUNT(customer_id) AS demographic_dist
FROM customer 
GROUP BY country, state, city
ORDER BY country;


-- --------------------------------------------------------------------------------------------------------------------------------------------------

/* 4.	Calculate the total revenue and number of invoices for each country, state, and city: */

SELECT 
	billing_country,
    billing_state,
    billing_city,
    SUM(total) AS total_revenue,
    COUNT(invoice_id) AS num_of_invoices
FROM invoice
GROUP BY billing_country, billing_state, billing_city
ORDER BY billing_country ASC,total_revenue DESC;


-- --------------------------------------------------------------------------------------------------------------------------------------------------

/* 5.	Find the top 5 customers by total revenue in each country */

WITH Top5CustomersCountryWise AS (
	SELECT 
		c.country, 
        CONCAT(c.first_name,' ',c.last_name) AS customer,
        SUM(i.total) AS total_revenue,
        RANK() OVER(PARTITION BY c.country ORDER BY SUM(i.total) DESC) AS countrywiseRank
	FROM customer c JOIN invoice i ON c.customer_id = i.customer_id
	GROUP BY c.country,c.first_name,c.last_name
)

SELECT 
	country,
    customer,
    total_revenue
FROM Top5CustomersCountryWise
WHERE countryWiseRank <= 5
ORDER BY country,total_revenue DESC;


-- --------------------------------------------------------------------------------------------------------------------------------------------------

/* 6.	Identify the top-selling track for each customer */

WITH CustomerTrackSales AS (
SELECT 
	c.customer_id, c.first_name, c.last_name,
    SUM(il.quantity) AS total_quantity,
    SUM(i.total) AS total_sales,
    ROW_NUMBER() OVER(PARTITION BY c.customer_id ORDER BY SUM(i.total) DESC) AS sales_rank
FROM customer c 
LEFT JOIN invoice i ON c.customer_id = i.customer_id
LEFT JOIN invoice_line il ON i.invoice_id = il.invoice_id
LEFT JOIN track t ON il.track_id = t.track_id
GROUP BY c.customer_id,c.first_name,c.last_name
)

SELECT 
	customer_id, CONCAT(first_name, ' ', last_name) AS customer_name, total_quantity,total_sales
FROM CustomerTrackSales 
WHERE sales_rank = 1
ORDER BY total_sales DESC;


-- --------------------------------------------------------------------------------------------------------------------------------------------------

/* 7.	Are there any patterns or trends in customer purchasing behavior (e.g., frequency of purchases, preferred payment methods, average order value)? */

/* 1. Purchase Frequency */

WITH PurchaseFrequency AS (
	SELECT 
		c.customer_id, 
        CONCAT(c.first_name,' ',c.last_name) AS customer_name, 
		COUNT(i.invoice_id) AS total_purchases, 
		MIN(DATE(i.invoice_date)) AS first_purchase_date, 
		MAX(DATE(i.invoice_date)) AS latest_purchase_date,
		ROUND(
			DATEDIFF(MAX(DATE(i.invoice_date)),MIN(DATE(i.invoice_date))) / 
            COALESCE(COUNT(i.invoice_id)-1, 0),0) AS avg_days_bet_purchases
	FROM customer c 
	JOIN invoice i ON c.customer_id = i.customer_id
	GROUP BY 1,2
)

SELECT * FROM PurchaseFrequency
ORDER BY avg_days_bet_purchases, total_purchases DESC;


/* 2. Average Order Value */

WITH CustomerPurchases AS (
	SELECT 
		c.customer_id, c.first_name, c.last_name,
		SUM(i.total) AS total_order_value, 
        COUNT(i.invoice_id) AS total_purchases,
        ROUND(AVG(i.total),2) AS avg_order_value
	FROM customer c 
    LEFT JOIN invoice i ON c.customer_id = i.customer_id
    GROUP BY c.customer_id, c.first_name, c.last_name
)

SELECT * FROM CustomerPurchases
ORDER BY avg_order_value DESC;


-- --------------------------------------------------------------------------------------------------------------------------------------------------

/* 8.	What is the customer churn rate? */

WITH PreviousCustomerPurchases AS (
    SELECT 
        c.customer_id,c.first_name,c.last_name,DATE(i.invoice_date) AS invoice_date,
        LEAD(DATE(i.invoice_date)) OVER(PARTITION BY c.customer_id ORDER BY invoice_date DESC) AS prev_purchase
    FROM customer c
    JOIN invoice i ON c.customer_id = i.customer_id
),

PrevPurchaseRank AS (
	SELECT 
		*,ROW_NUMBER() OVER(PARTITION BY customer_id ORDER BY prev_purchase DESC) AS prev_purchase_rn
	FROM PreviousCustomerPurchases
),

PreviousPurchaseDate AS (
	SELECT 
		*,DATEDIFF(invoice_date,prev_purchase) AS days_since_last_purchase
	FROM PrevPurchaseRank
	WHERE prev_purchase_rn = 1
	AND DATEDIFF(invoice_date,prev_purchase) > 180
	ORDER BY days_since_last_purchase DESC
)

SELECT 
	COUNT(pp.customer_id) AS churned_customers,
    COUNT(c.customer_id) AS total_customers,
    ROUND((COUNT(pp.customer_id) * 100) / COUNT(c.customer_id), 2) AS churn_rate
FROM customer c LEFT JOIN PreviousPurchaseDate pp ON c.customer_id = pp.customer_id;


-- --------------------------------------------------------------------------------------------------------------------------------------------------

/* 9.	Calculate the percentage of total sales contributed by each genre in the USA and identify the best-selling genres and artists. */

WITH SalesGenreRankUSA AS (
	SELECT
		g.name AS genre, ar.name AS artist, SUM(i.total) AS genre_sales,
        DENSE_RANK() OVER( PARTITION BY g.name ORDER BY SUM(i.total) DESC) AS genre_rank	
	FROM genre g
    LEFT JOIN track t ON g.genre_id = t.genre_id
    LEFT JOIN invoice_line il ON t.track_id = il.track_id
    LEFT JOIN invoice i ON il.invoice_id = i.invoice_id
    LEFT JOIN album a ON t.album_id = a.album_id
    LEFT JOIN artist ar ON a.artist_id = ar.artist_id
    WHERE i.billing_country = 'USA'
    GROUP BY 1,2
),

TotalSalesUSA AS (
	SELECT 
		SUM(i.total) AS total_sales
	FROM invoice_line il 
    LEFT JOIN invoice i ON il.invoice_id = i.invoice_id
    WHERE i.billing_country = 'USA'
)

SELECT s.genre,s.artist,s.genre_sales,t.total_sales, ROUND((s.genre_sales / t.total_sales)* 100,2) AS percent_sales
FROM SalesGenreRankUSA s JOIN TotalSalesUSA t
ORDER BY s.genre_sales DESC, s.genre ASC;


-- --------------------------------------------------------------------------------------------------------------------------------------------------

/* 10.	Find customers who have purchased tracks from at least 3 different genres */

SELECT 
	c.customer_id,
	CONCAT(c.first_name,' ',c.last_name) AS customer,
	COUNT(DISTINCT t.genre_id) AS genre_count,
	COUNT(DISTINCT t.track_id) AS track_count
	FROM customer c
	JOIN invoice i ON c.customer_id = i.customer_id
	JOIN invoice_line il ON i.invoice_id = il.invoice_id
	JOIN track t ON il.track_id = t.track_id
	JOIN genre g ON t.genre_id = g.genre_id
GROUP BY c.customer_id,c.first_name,c.last_name
HAVING COUNT(DISTINCT g.genre_id) >=3
ORDER BY genre_count DESC;


-- --------------------------------------------------------------------------------------------------------------------------------------------------

/* 11.	Rank genres based on their sales performance in the USA */

WITH SalesWiseGenreRank AS (
	SELECT
		g.name AS genre,
        SUM(i.total) AS total_sales,
        DENSE_RANK() OVER(ORDER BY SUM(i.total) DESC) AS genre_rank	
	FROM genre g
    LEFT JOIN track t ON g.genre_id = t.genre_id
    LEFT JOIN invoice_line il ON t.track_id = il.track_id
    LEFT JOIN invoice i ON il.invoice_id = i.invoice_id
    WHERE i.billing_country = 'USA'
    GROUP BY g.name
)    

SELECT
	genre,total_sales,genre_rank
FROM SalesWiseGenreRank
ORDER BY genre_rank;


-- --------------------------------------------------------------------------------------------------------------------------------------------------

/* 12.	Identify customers who have not made a purchase in the last 3 months */

WITH CustomerLastPurchase AS (
    SELECT 
        c.customer_id,
        c.first_name,
        c.last_name,
        MIN(DATE(i.invoice_date)) AS first_purchase_date,
        MAX(DATE(i.invoice_date)) AS last_purchase_date
    FROM customer c
    JOIN invoice i ON c.customer_id = i.customer_id
    GROUP BY c.customer_id, c.first_name, c.last_name
),
CustomerPurchases AS (
    SELECT 
        c.customer_id,
        c.first_name,
        c.last_name,
        DATE(i.invoice_date) AS invoice_date
    FROM customer c
    JOIN invoice i ON c.customer_id = i.customer_id
)
SELECT 
    clp.customer_id, 
    clp.first_name, 
    clp.last_name, 
    clp.first_purchase_date,
    clp.last_purchase_date
FROM CustomerLastPurchase clp
LEFT JOIN CustomerPurchases cp ON clp.customer_id = cp.customer_id 
AND cp.invoice_date BETWEEN clp.last_purchase_date - INTERVAL 3 MONTH AND clp.last_purchase_date - INTERVAL 1 DAY
WHERE cp.invoice_date IS NULL
ORDER BY clp.customer_id;


-- --------------------------------------------------------------------------------------------------------------------------------------------------


/*

SUBJECTIVE QUESTIONS

*/


/*1. Recommend the three albums from the new record label that should be prioritised for advertising and promotion in the USA based on genre sales analysis.*/

WITH RecommendedAlbums AS (
    SELECT 
		al.title AS album_name,
		a.name AS artist_name,
        g.name AS genre_name,
		SUM(i.total) AS total_sales,
        SUM(il.quantity) AS total_quantity,
		ROW_NUMBER() OVER(ORDER BY SUM(i.total) DESC) AS sales_rank
    FROM customer c 
    JOIN invoice i ON c.customer_id = i.customer_id
    JOIN invoice_line il ON i.invoice_id = il.invoice_id
    JOIN track t ON il.track_id = t.track_id
    JOIN album al ON t.album_id = al.album_id
    JOIN artist a ON al.artist_id = a.artist_id
    JOIN genre g ON t.genre_id = g.genre_id
    WHERE c.country = 'USA'
    GROUP BY al.title,a.name,g.name
)

SELECT * FROM RecommendedAlbums 
ORDER BY total_sales DESC;


-- ------------------------------------------------------------------------------------------------------------------------------------------

/*2. Determine the top-selling genres in countries other than the USA and identify any commonalities or differences.*/

SELECT g.name AS Genre, SUM(il.unit_price * il.quantity) AS Total_Sales
FROM invoice i
JOIN customer c ON i.customer_id = c.customer_id
JOIN invoice_line il ON i.invoice_id = il.invoice_id
JOIN track t ON il.track_id = t.track_id
JOIN genre g ON t.genre_id = g.genre_id
WHERE c.country <> 'USA'
GROUP BY g.name
ORDER BY Total_Sales DESC;

/*For Genres Within USA*/
SELECT g.name AS genre, SUM(il.unit_price * il.quantity) AS total_sales,
       RANK() OVER (ORDER BY SUM(il.unit_price * il.quantity) DESC) AS sales_rank
FROM invoice i
JOIN invoice_line il ON i.invoice_id = il.invoice_id
JOIN track t ON il.track_id = t.track_id
JOIN genre g ON t.genre_id = g.genre_id
WHERE i.billing_country = 'USA'
GROUP BY g.name
ORDER BY total_sales DESC;

    
-- ------------------------------------------------------------------------------------------------------------------------------------------

/*3. Customer Purchasing Behavior Analysis: How do the purchasing habits (frequency, basket size, spending amount) of long-term customers differ from those of new customers? What insights can these patterns provide about customer loyalty and retention strategies? */

WITH CustomerInvoiceDates AS (
	SELECT 
		c.customer_id,c.first_name, c.last_name, 
        MIN(DATE(i.invoice_date)) AS first_purchase_date,
        MAX(DATE(i.invoice_date)) AS last_purchase_date,
        COUNT(DISTINCT i.invoice_id) AS purchase_frequency,
        ROUND(AVG(il.quantity),0) AS avg_basket_size,
        ROUND(AVG(i.total),2) AS avg_spending_amount
    FROM customer c
    JOIN invoice i ON c.customer_id = i.customer_id
    JOIN invoice_line il ON i.invoice_id = il.invoice_id
    GROUP BY 1,2,3
),

CustomerCategory AS (
	SELECT 
		*,
        DATEDIFF(last_purchase_date,first_purchase_date) AS date_diff,
        CASE WHEN DATEDIFF(last_purchase_date,first_purchase_date) > 1000 THEN 'Long Term' ELSE 'New' END AS category_type
	FROM CustomerInvoiceDates
)

SELECT * FROM CustomerCategory
ORDER BY customer_id;


-- ------------------------------------------------------------------------------------------------------------------------------------------

/*4. Product Affinity Analysis: Which music genres, artists, or albums are frequently purchased together by customers? How can this information guide product recommendations and cross-selling initiatives? */

WITH ProductAffinityAnalysis AS (
	SELECT 
		c.customer_id,c.first_name,c.last_name,
		a.name AS artist_name,
        g.name AS genre_name,
        SUM(il.quantity) AS total_quantity,
        SUM(i.total) AS total_sales
        -- ,RANK() OVER(ORDER BY SUM(i.total) DESC) AS sales_rank
	FROM invoice i 
    LEFT JOIN invoice_line il ON i.invoice_id = il.invoice_id
    LEFT JOIN track t ON il.track_id = t.track_id
    LEFT JOIN album al ON t.album_id = al.album_id
    LEFT JOIN artist a ON al.artist_id = a.artist_id
    LEFT JOIN genre g ON t.genre_id = g.genre_id
    LEFT JOIN customer c ON i.customer_id = c.customer_id
	GROUP BY c.customer_id,c.first_name,c.last_name,a.name,g.name
    
)

SELECT * FROM ProductAffinityAnalysis 
ORDER BY customer_id, total_quantity DESC;


-- ------------------------------------------------------------------------------------------------------------------------------------------

/*5. Regional Market Analysis: Do customer purchasing behaviors and churn rates vary across different geographic regions or store locations? How might these correlate with local demographic or economic factors? */

WITH PreviousCustomerPurchases AS (
    SELECT 
		c.country,
        c.customer_id,c.first_name,c.last_name,DATE(i.invoice_date) AS invoice_date,
        LEAD(DATE(i.invoice_date)) OVER(PARTITION BY c.customer_id ORDER BY invoice_date DESC) AS prev_purchase
    FROM customer c
    JOIN invoice i ON c.customer_id = i.customer_id
),

PrevPurchaseRank AS (
	SELECT 
		*,ROW_NUMBER() OVER(PARTITION BY customer_id ORDER BY prev_purchase DESC) AS prev_purchase_rn
	FROM PreviousCustomerPurchases
),

PreviousPurchaseDate AS (
	SELECT 
		*,DATEDIFF(invoice_date,prev_purchase) AS days_since_last_purchase
	FROM PrevPurchaseRank
	WHERE prev_purchase_rn = 1
	AND DATEDIFF(invoice_date,prev_purchase) > 180
	ORDER BY days_since_last_purchase DESC
)

SELECT 
	c.country,
	COUNT(pp.customer_id) AS churned_customers,
    COUNT(c.customer_id) AS total_customers,
    ROUND((COUNT(pp.customer_id) * 100) / COUNT(c.customer_id), 2) AS churn_rate
FROM customer c LEFT JOIN PreviousPurchaseDate pp ON c.customer_id = pp.customer_id
GROUP BY c.country;


-- ------------------------------------------------------------------------------------------------------------------------------------------

/*6. Customer Risk Profiling: Based on customer profiles (age, gender, location, purchase history), which customer segments are more likely to churn or pose a higher risk of reduced spending? What factors contribute to this risk? */

WITH PreviousCustomerPurchases AS (
    SELECT 
		c.country,
        c.customer_id,c.first_name,c.last_name,DATE(i.invoice_date) AS invoice_date,
        LEAD(DATE(i.invoice_date)) OVER(PARTITION BY c.customer_id ORDER BY invoice_date DESC) AS prev_purchase
    FROM customer c
    JOIN invoice i ON c.customer_id = i.customer_id
),

PrevPurchaseRank AS (
	SELECT 
		*,ROW_NUMBER() OVER(PARTITION BY customer_id ORDER BY prev_purchase DESC) AS prev_purchase_rn
	FROM PreviousCustomerPurchases
),

PreviousPurchaseDate AS (
	SELECT 
		*,DATEDIFF(invoice_date,prev_purchase) AS days_since_last_purchase
	FROM PrevPurchaseRank
	WHERE prev_purchase_rn = 1
	AND DATEDIFF(invoice_date,prev_purchase) > 180
	ORDER BY days_since_last_purchase DESC
)

SELECT 
	c.country,
	COUNT(pp.customer_id) AS churned_customers,
    COUNT(c.customer_id) AS total_customers,
    ROUND((COUNT(pp.customer_id) * 100) / COUNT(c.customer_id), 2) AS churn_rate
FROM customer c LEFT JOIN PreviousPurchaseDate pp ON c.customer_id = pp.customer_id
GROUP BY c.country
ORDER BY churn_rate DESC, total_customers ASC;


-- ------------------------------------------------------------------------------------------------------------------------------------------

/*7. Customer Lifetime Value Modeling: How can you leverage customer data (tenure, purchase history, engagement) to predict the lifetime value of different customer segments? This could inform targeted marketing and loyalty program strategies. Can you observe any common characteristics or purchase patterns among customers who have stopped purchasing? */

WITH CustomerTenure AS (
    SELECT 
        c.customer_id, CONCAT(c.first_name,' ', c.last_name) AS customer,
        MIN(i.invoice_date) AS first_purchase_date,
        MAX(i.invoice_date) AS last_purchase_date,
        DATEDIFF(MAX(i.invoice_date), MIN(i.invoice_date)) AS tenure_days,
        COUNT(i.invoice_id) AS purchase_frequency,
        SUM(i.total) AS total_spent
    FROM customer c
    JOIN invoice i ON c.customer_id = i.customer_id
    GROUP BY c.customer_id
)

SELECT 
    customer_id,
    customer,
    tenure_days,
    purchase_frequency,
    total_spent,
    ROUND(total_spent / purchase_frequency, 2) AS avg_order_value,
    DATEDIFF(CURRENT_DATE, last_purchase_date) AS days_since_last_purchase
FROM CustomerTenure
ORDER BY days_since_last_purchase DESC;


-- ------------------------------------------------------------------------------------------------------------------------------------------

/*10. How can you alter the "Albums" table to add a new column named "ReleaseYear" of type INTEGER to store the release year of each album? */

ALTER TABLE album 
ADD COLUMN ReleaseYear INT(4);

SELECT * FROM album;


-- ------------------------------------------------------------------------------------------------------------------------------------------

/*11. Chinook is interested in understanding the purchasing behavior of customers based on their geographical location. They want to know the average total amount spent by customers from each country, along with the number of customers and the average number of tracks purchased per customer. Write a SQL query to provide this information. */

SELECT 
    c.country,
    ROUND(AVG(track_count)) AS average_tracks_per_customer,
    SUM(i.total) AS total_spent,
    COUNT(DISTINCT c.customer_id) AS no_of_customers,
    ROUND(SUM(i.total)/ COUNT(DISTINCT c.customer_id),2) AS avg_total_spent
    
FROM customer c
JOIN invoice i ON c.customer_id = i.customer_id
JOIN (
        SELECT 
            invoice_id, 
            COUNT(track_id) AS track_count
        FROM invoice_line
        GROUP BY invoice_id
) il ON i.invoice_id = il.invoice_id
GROUP BY c.country
ORDER BY avg_total_spent DESC;