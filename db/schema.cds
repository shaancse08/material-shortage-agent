namespace machbau.shortage;

using {
    cuid,
    managed
} from '@sap/cds/common';


using {API_MATERIAL_STOCK_SRV as MaterialExt} from '../srv/external/API_MATERIAL_STOCK_SRV';
using {API_PRODUCTION_ORDER_2_SRV as ProdOrderExt} from '../srv/external/API_PRODUCTION_ORDER_2_SRV';
using {API_PRODUCT_SRV as ProductExt} from '../srv/external/API_PRODUCT_SRV';


entity Materials           as
    projection on ProductExt.A_Product {
        Product,
        CreationDate,
        ProductType,
        ProductGroup,
        to_Valuation,
        to_ProductProcurement,
        @cds.odata.navigable
        to_Description : Association to MaterialDescription
                             on to_Description.Product = Product
    }

/**
 * Material description in a given language. This is a separate entity because S/4's product master data is multi-lingual, and the API_PRODUCT_SRV service returns one row per language.
 * The ShortageService service will typically query this entity with a filter on Language = 'EN
 */
entity MaterialDescription as
    projection on ProductExt.A_ProductDescription {
        ProductDescription,
        Product,
        Language
    }
    where
        Language = 'EN';

/**
 * Local materials master — supplements remote S/4 stock data with things
 * S/4's stock API won't give us directly for this demo: unit cost (for the
 * value-based auto-order limit) and substitute relationships.
 * Actual quantities-on-hand come from the remote API_MATERIAL_STOCK_SRV service,
 * NOT from this entity — this is deliberately not a stock duplicate.
 */
entity MaterialStock       as
    projection on MaterialExt.A_MatlStkInAcctMod {
        Material,
        Plant,
        StorageLocation,
        Batch,
        Supplier,
        Customer,
        WBSElementInternalID,
        SDDocument,
        SDDocumentItem,
        InventorySpecialStockType,
        InventoryStockType,
        WBSElementExternalID,
        MaterialBaseUnit,
        MatlWrhsStkQtyInMatlBaseUnit,
        productionOrders : Association to many ProductionOrders
                               on productionOrders.Material = Material
    }
    where
            Material is not null
        and Material !=     ''; // filter out the "dummy" material that S/4 sometimes returns

/**
 * A production order for a finished machine/product.
 * Deliberately multi-component (via ProductionOrderComponents), not single-material —
 * this is what makes shortage escalation realistic: one order can be fine on
 * 4 components and short on the 5th.
 */
entity ProductionOrders    as
    projection on ProdOrderExt.A_ProductionOrder_2 {
        ManufacturingOrder,
        Material,
        ProductionPlant,
        TotalQuantity,
        MfgOrderPlannedEndDate,
        OrderIsReleased,
        OrderIsCreated,
        OrderIsTechnicallyCompleted,
        OrderIsClosed,
        materialStock : Association to many MaterialStock
                            on materialStock.Material = Material
    }
