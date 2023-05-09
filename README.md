# SQLProjects

This repository contains a single project I've worked on, within an Academic context, that details the use o T-SQL on the AdventureWorks Database, following this business problem context

### IV. Stock Clearance - Functional specification
• Only products that are currently commercialized (both SellEndDate and DiscontinuedDate values not set).
• Initial bid price for products that are not manufactured in-house (MakeFlag value is 0) should be 75% of listed price
• For all other products initial bid prices should start at 50% of listed price
• By default, users can only increase bids by 5 cents (minimum increase bid) with maximum bid limit that is equal to initial product listed price. These thresholds should be easily configurable within a table so no need to change database schema model. Note: These thresholds should be global and not per product/category.

#### Stored procedures:
**Stored procedure name:** uspAddProductToAuction
**Stored procedure parameters:** @ProductID [int], @ExpireDate [datetime], @InitialBidPrice [money]
**Description:** This stored procedure adds a product as auctioned.
**Notes:** Either @ExpireDate and @InitalBidPrice are optional parameters. If @ExpireDate is not specified, then auction should end in one week. If initial bid price is not specified, then should be 50% of product listed price unless falls into one exclusion mentioned above. Only one item for each ProductID can be simultaneously enlisted as an auction.

**Stored procedure name:** uspTryBidProduct
**Stored procedure parameters:** @ProductID [int], @CustomerID [int], @BidAmount [money]
**Description:** This stored procedure adds bid on behalf of that customer
**Notes:** @BidAmount is an optional parameter. If @BidAmount is not specified, then increase by threshold specified in thresholds configuration table.

**Stored procedure name:** uspRemoveProductFromAuction
**Stored procedure parameters:** @ProductID [int]
**Description:** This stored procedure removes product from being listed as auctioned even there might have been bids for that product.
**Notes:** When users are checking their bid history this product should also show up as auction cancelled

**Stored procedure name:** uspListBidsOffersHistory
**Stored procedure parameters:** @CustomerID [int], @StartTime [datetime], @EndTime [datetime], @Active [bit]
**Description:** This stored procedure returns customer bid history for specified date time interval. If Active parameter is set to false, then all bids should be returned including ones related for products no longer
