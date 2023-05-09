use AdventureWorks

Drop table Auction.BidHistory
Drop table Auction.InAuctionProducts
Drop table Auction.StartingPrice
Drop table Auction.TerminatedProducts
Drop Schema Auction



-- 00. Create Schema Auction, if it already exists then pass
IF NOT EXISTS ( SELECT  *
                FROM    sys.schemas
                WHERE   name = N'Auction' )
    EXEC('CREATE SCHEMA [Auction]');


-- 01. Create StartingPrice Table
/*	EXPLANATION COMMENT
	This table will have all the ProductID's of the products that can go to auction (products that meet the predefined criteria)
	their correspondent ListPrices (the prices to which the product is sold to the public) 
	and the InitialBidPrices that are the minimum initial BidPrice for each product.

	This table will serve as a comparison point for the first Stored Procedure that will add a product to the Auction and check if the inputed values 
	match the ones that are here as a reference
*/	
IF  NOT EXISTS (SELECT * FROM sys.objects 
WHERE object_id = OBJECT_ID(N'Auction.StartingPrice') AND type in (N'U'))
BEGIN
SELECT	
	ProductID, ListPrice,	-- Maybe we don't need the ListPrice, only the BidPrice?
CASE
	-- If MakeFlag = 1, manufactured in house, then the price to begin the auction will be 50% of the ListedPrice, otherwise it will be 75% of the ListedPrice
	WHEN MakeFlag = 1 THEN ListPrice * 0.5
	WHEN MakeFlag = 0 THEN ListPrice * 0.75
	ELSE ListPrice
END AS InitialBidPrice -- For this newly created feature we named it InitialBidPrice
INTO 
    Auction.StartingPrice -- Here we are placing these calculations and values obtained from the Production.Product Table into a new table named Auction.StartingPrice
FROM    
    Production.Product
Where 
	-- With this Where Statement we are meeting the conditions required at the beginnning of the exercise in which SellEndDate and DiscontinuedDate are not set
	-- We are also setting that we only want the products that have the FinishedGoodsFlag = 1 to only consider the products that 
	Product.SellEndDate Is null and Product.DiscontinuedDate is null and Product.FinishedGoodsFlag = 1;
End;



-- 02. Create InAuctionProducts & Create TransactionsTable & Terminated Products table
/*	EXPLANATION COMMENT for InAutctionProducts
	This table is the one that is going to be used for having the products that are being auctioned at each time
	Anytime a new product is going to be auctioned it will be placed in here with the CustomerID that has the highestBid
	Here only 4 features are necessary, the ProductID of the product being Auctioned now
	the CurrentBidPrice (that can be inputed by the user)
	the AuctionExpireDate (that can be inputed by the user)
	the CustomerID (That we still need to understand how will this be placed in here since is not a required field

	For this table it will exist, at most " Count(*) from Auction.StartingPrice " entries, since we can only have one auction per item occurring at the same time
	If an auction for a product that is already being auctioned is propesed then it will be redirectioned to the currently being auctioned product

	EXPLANATION COMMENT for BidHistory
	This table will have the register of all transactions that occured

	EXPLANATION COMMENT FOR TerminatedProducts
	This table will have the information regarding all auctions that have been terminated, based on
*/

IF  NOT EXISTS (SELECT * FROM sys.objects 
	WHERE object_id = OBJECT_ID(N'Auction.InAuctionProducts') AND type in (N'U'))
	BEGIN
		Create Table Auction.InAuctionProducts (
		ProductID int,
		CurrentBidPrice money,
		AuctionExpireDate datetime,
		CustomerID int,
		AuctionNumber int
		)
End;
IF  NOT EXISTS (SELECT * FROM sys.objects 
	WHERE object_id = OBJECT_ID(N'Auction.BidHistory') AND type in (N'U'))
	BEGIN
		Create Table Auction.BidHistory (
		CustomerID int,
		ProductID int,
		BidAmount money,
		TransactionDate datetime,
		AuctionNumber int,
		ProductStatus varchar(50)
		)
End;
IF  NOT EXISTS (SELECT * FROM sys.objects 
	WHERE object_id = OBJECT_ID(N'Auction.TerminatedProducts') AND type in (N'U'))
	BEGIN
		Create table Auction.TerminatedProducts (
		ProductID int,
		BidPrice money,
		AuctionExpireDate datetime,
		CustomerID int,
		AuctionNumber int,
		ProductStatus varchar(50)
		)
End;
Go



-- 03. Create Stored Procedure
-- 1st Stored Procedure
/*	EXPLANATION COMMENT
	This stored procedure will update one entry in the table InAuctionProducts.

	If @BidPrice is not given then we are retrieving this value from the StartingPrice table, from column InitialBidPrice
	This column already has the initial bid price that each product must have
		this will then be checked against all the products that 
	
	With this Stored Procedure we are only creating an entry on the InAuction table for the product. Here we are not trying to do any bid
		on the product, we are only defining the initial conditions
*/
Create or alter Procedure uspAddProductToAuction(@ProductID int, @ExpireDate datetime = NULL, @InitialBidPrice money = NULL)
-- We are defining @ProductID as a mandatory parameter, and the other two as optional with initial value equal to Null
As
Begin
-- Check if ProductID exists

if (SELECT count(*) FROM Auction.StartingPrice WHERE ProductID = @ProductID) = 0
	-- Condition to verify if there is any entry associated with the ProductID that was inputed on the Stored Procedure on the StartingPrice table
	Begin
		print 'The inputed ProductID does not exist on the database. Plase confirm the ProductID and re-run the storedProcedure'
		Return --This returns nothing and ends the stored procedure
	End;

-- InputedBidPrice manipulation
Declare @InputedBidPrice money = @InitialBidPrice
	-- Here we are declaring a new variable for name uniformisation inside the Stored Procedure
IF (@InputedBidPrice IS NULL OR @InputedBidPrice = '') -- Handling if the value is not filled
	Begin
		Select @InputedBidPrice = InitialBidPrice from Auction.StartingPrice
		Where ProductID = @ProductID
	End;
	-- If the @InputedBidPrice is null (because is not a mandatory variable then we will retrieve the value from the Auction.StartingPrice 
		-- table that we already created for the ProductID that we are trying to auction

-- @InputedFinalExpireDate manipulation
Declare @InputedFinalExpireDate date = @ExpireDate
IF (@InputedFinalExpireDate IS NULL OR @InputedFinalExpireDate = '') 
	Begin
		Select @InputedFinalExpireDate = dateadd(day, 7, getdate())
	End
	-- If the ExpireDate is not setted-up by the user then it will be defined as today (the date in which the product is being auctioned) + 7 days

	declare @MaximumBidPrice as money
	Select @MaximumBidPrice = ListPrice  from Auction.StartingPrice Where ProductID = @ProductID

	declare @MinimumBidPrice as money
	Select @MinimumBidPrice = InitialBidPrice  from Auction.StartingPrice Where ProductID = @ProductID

-- Check if it's the first product with this ProductID to be added to the table
if (SELECT count(*) FROM Auction.InAuctionProducts WHERE ProductID = @ProductID) > 0
	-- Condition to verify if there is any entry associated with the ProductID that was inputed on the Stored Procedure on the current InAuctionProducts table
	Begin
	-- Now that we know that this product is already being auctioned then we need to report an error message saying that can't exist 2 equal products being auctioned at the same time

	print 'This product is already being auctioned, please re-do the auction atempt.'
	Return --This returns nothing and ends the stored procedure
	End
Else
	-- meaning that there is no product for this item being auctioned right now
	Begin
		if @InputedBidPrice > @MaximumBidPrice
		Begin
			print 'The inputed Bid amount is above the maximum limit for this product'
			return
		End

		if @InputedBidPrice < @MinimumBidPrice
			Begin
				print 'The inputed Bid amount is below the minimum limit for this product'
				return 
			End

		/* Comment 
		We also need to define the AuctionNumber for this product because although we know that the product is not on the InAuctionProducts
			we can't be sure if it already existed in previous auctions
		*/

		Declare @AuctionNumber_temp as int
		Select @AuctionNumber_temp = max(AuctionNumber) from Auction.TerminatedProducts where ProductID = @ProductID -- Get the value of the last AuctionNumber

		if @AuctionNumber_temp is null
		-- Here we have the situation in which the product is not being auctioned and has never been auctioned, this this variable is null
			Begin
				Select @AuctionNumber_temp = 1
			End
		Else
		-- Here we have the situation in which the product is not being auctioned, but has already been auctioned, therefore we need to place the correct AuctionNumber on the BidHistory
			Begin
				Select @AuctionNumber_temp = @AuctionNumber_temp + 1 -- Meaning that we will place this bet on a new
			End

		Insert into Auction.InAuctionProducts
		Values (@ProductID, @InputedBidPrice, @InputedFinalExpireDate, Null, @AuctionNumber_temp) 
	End;
End
Go


 -- 2nd Stored Procedure

 /* EXPLANATION COMMENT
	This stored procedure will create a bid, for the customer, checking if the product can be bid on, if the price range is correct
		(and if not to replace that by an acceptable bid price)

 */
Create or Alter Procedure uspTryBidProduct(@ProductID int, @CustomerID int, @BidAmount money = Null)

As
-- 2.1. Check if the product exists on the InAuctionProducts Table
	-- If the product does not exist then we should call the first stored procedure that creates the product on the InAuctionProducts


if (SELECT count(*) FROM Auction.InAuctionProducts WHERE ProductID = @ProductID) > 0
	Begin
		-- If the product does exist on the InAuctionProducts table
		print ''
		-- The code for the statement if the product exists is not being placed here for ease of reading so we've placed it after the if statement has ended
	End
Else
	Begin
		-- Here the product doesn't exist therefore we are executing the code to create a new auction
		Declare @standardBidAmount as money
		if @BidAmount is Null
			-- Here the user didn't inputed any BidAmount so we will execute the 1st StoredProcedure without it
			Begin
				print 'afinal e null e ficou aqui' 
				Exec uspAddProductToAuction @ProductID -- Adding the product to the InAuctionProducts Table
				print 'The specified product does not exist in the table of products being auctioned therefore a new auction for this product has been created with the standard
				values for the duration of the auction and the initial bid amount'
				-- Replacing the CustomerID for the higher bid offer of that product on the table
				Update Auction.InAuctionProducts
				Set
					CustomerID = @CustomerID
				Where
					ProductID = @ProductID;	
				
				Select @standardBidAmount = InitialBidPrice from Auction.StartingPrice where ProductID = @ProductID
				print 'standardBidamount'
				print @standardBidAmount
			End
		Else
			-- Here the user has inputed a BidAmount so there will be executed the code for the 1st StoredProcedure, using it
			Begin
				Select @standardBidAmount = @BidAmount
				Exec uspAddProductToAuction @ProductID, @InitialBidPrice = @standardBidAmount

				print 'The specified product does not exist in the table of products being auctioned therefore a new auction for this product has been created with the standard
				values for the duration of the auction. The BidAmount will be tested to pass the criteria defined for the product'

				Update Auction.InAuctionProducts
				Set
					CustomerID = @CustomerID
				Where
					ProductID = @ProductID;
			End
		/* Comment 
		When the code reaches here then we know that it was not being auctioned and that now it is already present on the InAuctionProducts table,
			this means that this entry is the first one relative to this specific product. Although it may not be the first time a product like this is auctioned
			i.e. Product A is being auctioned for the very first time, therefore it has no entry on the TerminatedProducts table, and it has no previous entry on the
			InAuctionProducts table, so its AuctionNumber = 1
				but Product B is being auctioned now, but the same product has already been auctioned previously, and so it's name appears on the TerminatedProducts
				table, therfore the AuctionNumber would have to be higher than 1
		We need to record this transitions on the BidHistory table with the correct AuctionNumber
		*/

		-- Update the BidHistory table with the bid that has just been done as the base payment

		 -- Define the AuctionNumber for the item
		Declare @AuctionNumber_temp as int
		Select @AuctionNumber_temp = max(AuctionNumber) from Auction.TerminatedProducts where ProductID = @ProductID -- Get the value of the last AuctionNumber

		if @AuctionNumber_temp is null
		-- Here we have the situation in which the product is not being auctioned and has never been auctioned, this this variable is null
			Begin
				Select @AuctionNumber_temp = 1
			End
		Else
		-- Here we have the situation in which the product is not being auctioned, but has already been auctioned, therefore we need to place the correct AuctionNumber on the BidHistory
			Begin
				Select @AuctionNumber_temp = @AuctionNumber_temp + 1 -- Meaning that we will place this bet on a new
			End
		Insert into Auction.BidHistory
		values (@CustomerID, @ProductID, @standardBidAmount, getdate(), @AuctionNumber_temp, 'InAuction');
		return 
	End

-- If the code reaches here then we are in the situation that the product exists in the InAuction Table so we wil check if the inputed parameters are 
	-- enough to replace the current bid

-- 2.2. Check the CurrentBidPrice for the product
Declare @CurrentBidPrice as money
Select @CurrentBidPrice = CurrentBidPrice  from Auction.InAuctionProducts Where ProductID = @ProductID
	-- The inputed BidPrice has to be at leat 5 cents above the @CurrentBidPrice
if @BidAmount >= (@CurrentBidPrice + 0.05)
	Begin
		print ''
	End
Else
	Begin
		-- If the BidAmount is not high enough then the following error message will appear and the StoredProcedure will break
		print 'The inputed amount is not high enough to replace the current bid. Please re-do your bid taking into consideration that '
		+ cast(@CurrentBidPrice as Varchar) + ' is the Current Bid Price for the item and each bid has to be at least 5 cents of the latest highest bid price'
		return 
	End;

-- 2.3. Check if the BidAmountis equal or inferior to the ListedPrice for that item
Declare @MaximumBid as money
Select @MaximumBid = ListPrice from Auction.StartingPrice where ProductID = @ProductID

if @BidAmount <= @MaximumBid
	Begin
		print''
	End
Else
	Begin
		-- Meaning that the BidAmount is above the maximum price for that item on the Auction
		-- If the BidAmount is not high enough then the following error message will appear and the StoredProcedure will break
		print 'The inputed amount is higher than the macimum amount for this product. Please re-do your bid taking into consideration that '
		+ cast(@CurrentBidPrice as Varchar) + ' is the highest bid amount for this product'
		return 
	End;

-- If the code reaches here then the BidAmount meets all the required criteria.
	-- Since we are considering heavy traffic on the website the code will re-check the calculation and try to replace the current value, else will return an error message

Begin Transaction
-- Update value for CurrentBidPrice after the checks were concluded
Select @CurrentBidPrice = CurrentBidPrice  from Auction.InAuctionProducts Where ProductID = @ProductID

 -- Defining the Update statement
Update Auction.InAuctionProducts
	Set
		CustomerID = @CustomerID,
		CurrentBidPrice = @BidAmount
	Where
		ProductID = @ProductID;

if (@BidAmount >= @CurrentBidPrice + 0.05)
	Begin
		Commit Transaction

		Declare @AuctionNumber_temp2 as int
		Select @AuctionNumber_temp2 = AuctionNumber from Auction.InAuctionProducts where ProductID = @ProductID

		-- Update on the BidHistory table
		Insert into Auction.BidHistory
		values (@CustomerID, @ProductID, @standardBidAmount, getdate(), @AuctionNumber_temp2, 'InAuction');
	End
Else
	Begin
		Rollback Transaction
		print 'The inputed amount is not high enough to replace the current bid. Please re-do your bid taking into consideration that '
		+ cast(@CurrentBidPrice as Varchar) + ' is the Current Bid Price for the item'
		return
	End

/*
Now that we already have the product placed on the table, we need to verify which AuctionNumber this product corresponds to
	i.e. if it is the first product with ProductID = 10 to be auctioned then it will have AuctionNumber = 10, but if it is the second it should have this parameter = 2
*/
if (SELECT count(*) FROM Auction.InAuctionProducts WHERE ProductID = @ProductID and AuctionNumber is null) > 0
	Begin
		-- Check if the product that we are auctioning has AuctionNumber as a null value

		if (SELECT count(*) FROM Auction.TerminatedProducts WHERE ProductID = @ProductID) > 0
		-- Check if the product exists on the TerminatedProducts table
			Begin
				-- If the code reaches here then the product has already been auctioned and so there is a value for the AuctionNumber but this is the first time it is being auctioned
				Declare @LatestAuction as int
				Select @LatestAuction = max(AuctionNumber) +1 from Auction.TerminatedProducts where ProductID = @ProductID -- Get the value of the last AuctionNumber
				
				Update Auction.InAuctionProducts
					Set AuctionNumber = @LatestAuction
					Where ProductID = @ProductID;
			End
		Else
			Begin
				-- Here the products doesn't exist on the TerminatedProducts therefore is the first time this product is being auctioned
				Update Auction.InAuctionProducts
					Set AuctionNumber = 1
					Where ProductID = @ProductID;
			End
	End

Go


-- 3rd Stored Procedure - Delete row associated with product in the InAuctionProducts
/*	EXPLANATION COMMENT
	This stored procedure deletes the row in the InAuctionProducts table that is associated with that product
		(Considering both th ProductID and the AuctionNumber associated)

	On the table BidHistory it also changes the ProductStatus to Cancelled so that when the BidHistory is to be retrieved the user can see which products 
		were cancelled by the Administrator
*/
Create or alter procedure uspRemoveProductFromAuction(@ProductID int)
-- For this sp we are only using the ProductID as an input, and the only task needed is to remove the row associated with it on the InAuction table
As Begin
If exists(SELECT * FROM Auction.InAuctionProducts where ProductID = @ProductID)
	Begin
		Declare @AuctionNumber as int
		Select @AuctionNumber = AuctionNumber from Auction.InAuctionProducts Where ProductID = @ProductID -- Get the AuctionNumber for this product

		-------
		-- Declare some more variables for alter use
		Declare @CurrentBidPrice as money
		Select @CurrentBidPrice = CurrentBidPrice from Auction.InAuctionProducts Where ProductID = @ProductID -- Get the AuctionNumber for this product

		Declare @AuctionExpireDate as datetime
		Select @AuctionExpireDate = AuctionExpireDate from Auction.InAuctionProducts Where ProductID = @ProductID -- Get the AuctionNumber for this product

		Declare @CustomerID as int
		Select @CustomerID = CustomerID from Auction.InAuctionProducts Where ProductID = @ProductID -- Get the AuctionNumber for this product
		-------

		-- If the product does exist
		Delete From Auction.InAuctionProducts Where ProductID = @ProductID
	End
Else
	Begin
		print 'The specified product does not exist in the table of products being auctioned'
		return 
	End;

-- If the product is retrieved via this parameter then we will change the ProductStatus value on the BidHistory table to 'Canceled'
-- Check if the product exists on the BidHistory

if (SELECT count(*) FROM Auction.BidHistory WHERE ProductID = @ProductID and AuctionNumber = @AuctionNumber) > 0
	Begin
		Update Auction.BidHistory
		Set ProductStatus = 'Cancelled'
		Where ProductID = @ProductID and AuctionNumber = @AuctionNumber
	End

-- Update the Auction.TerminatedProducts to have the information that was on the Auction.InAuctioProducts table
Insert into Auction.TerminatedProducts
	Values (@ProductID, @CurrentBidPrice, @AuctionExpireDate, @CustomerID, @AuctionNumber, 'Cancelled');

End
Go


-- 4th Stored Procedure - Returns all the Bid History for a specified time interval
/*
If Active = True then there is only returned the bid for all the products that are currently being auctioned,
	if it's = False then we are retrieving data for all products regardless of the auction status
This procedure will do a subset of the products of the table that is also being fed on the 2nd Stored Procedure
*/
Create or alter procedure uspListBidsOffersHistory(@CustomerID int, @StartTime datetime, @EndTime datetime, @Active bit = 'True')

As
Begin
-- Check if any bid was made with that CustomerID
if (SELECT count(*) FROM Auction.BidHistory WHERE CustomerID = @CustomerID) < 1
	Begin
		-- Meaning that there is no entry with this CustomerID
		print 'There is no transaction recorded while using this ProductID. Please confirm the input data and re-run the Stored Procedure'
		Return
	End

-- Check if EndTime is biger than StartTime
if @EndTime <= @StartTime
	Begin
		print 'The inputed EndTime is smaller than the inputed StartTime, please review the inputed data'
		Return 
	End

if @Active = 'False'
	Begin
		Select * from Auction.BidHistory Where CustomerID = @CustomerID
	End
Else
	-- Meaning that we should only retrieve data from auctions that are still being carried out (True)
	Begin
		Select Auction.BidHistory.CustomerID, Auction.BidHistory.ProductID, Auction.BidHistory.BidAmount, Auction.BidHistory.TransactionDate, Auction.BidHistory.AuctionNumber, Auction.BidHistory.ProductStatus
		From Auction.BidHistory
		Left Join Auction.InAuctionProducts on Auction.BidHistory.ProductID = Auction.InAuctionProducts.ProductID
		Where 
			Auction.BidHistory.CustomerID = @CustomerID and
			Auction.InAuctionProducts.ProductID = Auction.BidHistory.ProductID and 
			Auction.InAuctionProducts.AuctionNumber = Auction.BidHistory.AuctionNumber
	End
End
Go


 -- 5th Stored Procedure
Create or alter procedure uspUpdateProductAuctionStatus
/* EXPLANATION COMMENT
This table will update the Status for all products that are being auctioned, changing it to 'Terminated' if the current date is higher than the AuctionExpireDate

Detail True and False, which one does what.
*/

As
Begin
	Begin Transaction -- To lock both tables until its done writing all the data in both
	-- Insert data on the TerminatedProducts table
		
		Insert Into Auction.TerminatedProducts
			Select Auction.InAuctionProducts.ProductID, Auction.InAuctionProducts.CurrentBidPrice, Auction.InAuctionProducts.AuctionExpireDate, Auction.InAuctionProducts.CustomerID, Auction.InAuctionProducts.AuctionNumber, 'Terminated'
			from Auction.InAuctionProducts
			Left join Auction.StartingPrice on Auction.InAuctionProducts.ProductID = Auction.StartingPrice.ProductID
			Where Auction.InAuctionProducts.CurrentBidPrice >= Auction.StartingPrice.ListPrice or getdate() >= Auction.InAuctionProducts.AuctionExpireDate

	-- Remove data from InAuctionProducts table based on the same conditions
		Delete Auction.InAuctionProducts
			from Auction.InAuctionProducts
			Left join Auction.StartingPrice on Auction.InAuctionProducts.ProductID = Auction.StartingPrice.ProductID
			Where Auction.InAuctionProducts.CurrentBidPrice >= Auction.StartingPrice.ListPrice or getdate() >= Auction.InAuctionProducts.AuctionExpireDate

	--Update the informaton on the BidHistory table
		Update
			Auction.BidHistory
		Set 
			ProductStatus = 'Terminated'
		From 
			Auction.BidHistory
		join Auction.TerminatedProducts on Auction.BidHistory.ProductID = Auction.TerminatedProducts.ProductID and Auction.BidHistory.AuctionNumber = Auction.TerminatedProducts.AuctionNumber
	
	
	Commit Transaction

/*
		Update Auction.BidHistory
		Set ProductStatus = 'Terminated'
		from Auction.BidHistory
			left join Auction.TerminatedProducts on Auction.BidHistory.ProductID = Auction.TerminatedProducts.ProductID
				Where Auction.TerminatedProducts.ProductStatus = 'Terminated' and 
				Auction.TerminatedProducts.AuctionNumber = Auction.BidHistory.AuctionNumber
	Commit Transaction
	*/

End
Go

--- Tests
-- 1. Create an Auction 
Execute uspAddProductToAuction 680
	Select * from Auction.InAuctionProducts -- We expect one product here with AuctionNumber = 1 and Bid equal to the standard bid of the product and no CustomerID associated
	Select * from Auction.BidHistory -- We expect this table to be empty
	
Execute uspAddProductToAuction 680 -- Create auction for the same product
	Select * from Auction.InAuctionProducts -- We expect one product here with AuctionNumber = 1 and Bid equal to the standard bid of the product and no CustomerID associated
	Select * from Auction.BidHistory -- We expect this table to be empty

Execute uspAddProductToAuction 706,Null,714 -- Create auction for a new product but with a bid below the MinimumBid
	Select * from Auction.InAuctionProducts -- We expect one product here with AuctionNumber = 1 and Bid equal to the standard bid of the product and no CustomerID associated
	Select * from Auction.BidHistory -- We expect this table to be empty

Execute uspAddProductToAuction 706,Null,1000000 -- Create auction for a new product but with a bid above the MaximumBid
	Select * from Auction.InAuctionProducts -- We expect one product here with AuctionNumber = 1 and Bid equal to the standard bid of the product and no CustomerID associated
	Select * from Auction.BidHistory -- We expect this table to be empty

Execute uspAddProductToAuction 706,Null,1000 -- Create auction for a new product with an acceptable bid
	Select * from Auction.InAuctionProducts -- We expect twi products here with AuctionNumber = 1 and Bid equal to the standard bid of the product and no CustomerID associated and one with the inputed bid
	Select * from Auction.BidHistory -- We expect this table to be empty

Execute uspAddProductToAuction 100000 -- Create auction for a new product that doesn't exist
	Select * from Auction.InAuctionProducts -- We expect no changes on the table
	Select * from Auction.BidHistory -- We expect this table to be empty


-- 2. Try Bids
Execute uspTryBidProduct 680, 23 -- Place a bid with no BidAmount defined
	Select * from Auction.InAuctionProducts -- We expect no changes on the BidAmount for product 680 sine the user has to input the bid amount manually
	Select * from Auction.BidHistory -- We expect this table to be empty


Execute uspTryBidProduct 680, 23, 715 -- Place a bid with an lower Bid than the CurrentBid
	Select * from Auction.InAuctionProducts -- We expect no changes on the BidAmount for product 680 sine the user has to input the bid amount manually
	Select * from Auction.BidHistory -- We expect this table to be empty

Execute uspTryBidProduct 680, 23, 1500 -- Place a bid with an higher Bid than the CurrentBid
	Select * from Auction.InAuctionProducts -- We expect no changes on the BidAmount for product 680 sine the user has to input the bid amount manually
	Select * from Auction.BidHistory -- We expect this table to be empty

Execute uspTryBidProduct 680, 23, 1000 -- Place a bid with an acceptable BidAmount
	Select * from Auction.InAuctionProducts -- We expect to see the CustomerID and the BidAmount updated for the product
	Select * from Auction.BidHistory -- We expect this table to have one entry regarding the Bid that was made by customer 23

Execute uspTryBidProduct 680, 24, 1001 -- Place a bid with an acceptable BidAmount but from other customer
	Select * from Auction.InAuctionProducts -- We expect to see the CustomerID and the BidAmount updated for the product since it met the criteria
	Select * from Auction.BidHistory -- We expect this table to have one more entry regarding the latest bid from customer 24

Execute uspTryBidProduct 707, 707 -- Place a bid on a product that is not being auctioned
	Select * from Auction.InAuctionProducts -- We expect to see the new prroduct appearing and to see the CustomerID and the BidAmount updated for the product
	Select * from Auction.BidHistory -- We expect this table to have one more entry, regarding the new product 707 from customer 707

-- 3. Remove a Product from Auction
	Select * from Auction.TerminatedProducts -- We expect this table to be empty
	Select * from Auction.BidHistory -- We expect this table to have all products with ProductStatus = "InAuction"

Execute uspRemoveProductFromAuction 680-- removes a product from the InAuctionTable
	Select * from Auction.InAuctionProducts -- We expect for product 680 to be gone from this table
	Select * from Auction.TerminatedProducts -- We expect this table to have one entry which is the product 680 
	Select * from Auction.BidHistory -- We expect to have the same number of rows as before but now with the ProductStatus of all entries of product 680 to be set to Canceled

Execute uspRemoveProductFromAuction 1000-- removes a product that is not being auctioned right now
	Select * from Auction.InAuctionProducts -- We expect no change
	Select * from Auction.TerminatedProducts -- We expect no change
	Select * from Auction.BidHistory -- We expect no change

	-- 3.1 . Let's re-update the same product that has been removed back again into the Auction with the same customer
Execute uspTryBidProduct 680, 23, 1000
	Select * from Auction.InAuctionProducts -- We expect the product to appear again on the table and now with AuctionNumber = 2
	Select * from Auction.TerminatedProducts -- We expect no change
	Select * from Auction.BidHistory -- We expect one more entry on this table

-- 4. Get the BidHistory for the Customer
Execute uspListBidsOffersHistory 23, '2022-05-01 20:15:00', '2022-05-05 20:15:00', 'False'
	-- We expect no change in any table, and we expect to have all bid's registered for customer 23 regardless if the auction as already finished or not

Execute uspListBidsOffersHistory 23, '2022-05-01 20:15:00', '2022-05-05 20:15:00', 'True'
	-- We expect no change in any table, and we expect to have all bid's registered for customer 23 but only for products that are still being auctioned

Execute uspListBidsOffersHistory 23, '2022-05-02 20:15:00', '2022-05-01 20:15:00', 'False'
	-- We expect an error to pop-up because the EndDate is smaller than the StartDate

Execute uspListBidsOffersHistory 1000, '2022-05-01 20:15:00', '2022-05-02 20:15:00', 'True'
	-- We expect an error to pop-up because the customerID inputed has no recorded transaction on BidHistory

-- 5. Update Status of each product
	Select * from Auction.InAuctionProducts
	Select * from Auction.TerminatedProducts
Execute uspUpdateProductAuctionStatus
	Select * from Auction.InAuctionProducts -- We expect no changes in here because neither criteria has been met (ExpireDate < CurrentDate & BidAmount < ListPrice)
	Select * from Auction.TerminatedProducts -- We expect no changes in here because neither criteria has been met (ExpireDate < CurrentDate & BidAmount < ListPrice)

-- 5.1. And if we add a new bid that matches the ListPrice for the item?
Execute uspTryBidProduct 800, 1000, 1120.49
	Select * from Auction.InAuctionProducts
	Select * from Auction.TerminatedProducts
Execute uspUpdateProductAuctionStatus
	Select * from Auction.InAuctionProducts -- We expect for product 800 that was placed by customer 1000 to be removed from this table and to be placed on TerminatedProducts table
	Select * from Auction.TerminatedProducts
	Select * from Auction.BidHistory -- We also expect for the transactions that match this product with this AuctionNumber to be updated on the BidHistory table to Terminated

-- 5.2. And if we add a product with a bid and with a BidDate higher than the ExpireDate?
Execute uspAddProductToAuction 800, '2022-01-01 00:00:00'
Execute uspTryBidProduct 800, 1000, 700
Execute uspUpdateProductAuctionStatus
	Select * from Auction.InAuctionProducts -- We expect for product 800 that was placed by customer 1000 to be removed from this table and to be placed on TerminatedProducts table
	Select * from Auction.TerminatedProducts
	Select * from Auction.BidHistory -- We also expect for the transactions that match this product with this AuctionNumber to be updated on the BidHistory table to Terminated
