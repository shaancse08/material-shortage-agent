namespace machbau.shortage;

using {
    cuid,
    managed
} from '@sap/cds/common';


using {API_MATERIAL_STOCK_SRV as MaterialExt} from '../srv/external/API_MATERIAL_STOCK_SRV';
using {API_PRODUCTION_ORDER_2_SRV as ProdOrderExt} from '../srv/external/API_PRODUCTION_ORDER_2_SRV';

/**
 * Local materials master — supplements remote S/4 stock data with things
 * S/4's stock API won't give us directly for this demo: unit cost (for the
 * value-based auto-order limit) and substitute relationships.
 * Actual quantities-on-hand come from the remote API_MATERIAL_STOCK_SRV service,
 * NOT from this entity — this is deliberately not a stock duplicate.
 */
entity Materials        as
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

/**
 * A production order for a finished machine/product.
 * Deliberately multi-component (via ProductionOrderComponents), not single-material —
 * this is what makes shortage escalation realistic: one order can be fine on
 * 4 components and short on the 5th.
 */
entity ProductionOrders as
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
        materials : Association to many Materials
                        on materials.Material = Material
    }

entity ProductionOrderComponents : cuid {
    order            : Association to ProductionOrders;
    material         : Association to Materials @mandatory;
    quantityRequired : Integer                  @mandatory;
}

/**
 * Config for the deterministic auto-order boundary. Value-based (cost), not quantity-based —
 * 500 units of a €0.01 screw is nothing; 5 units of a €10,000 motor is a big deal.
 * Kept as a single-row/category config, not hardcoded in application logic.
 */
entity AutoOrderPolicy : cuid {
    category            : String(20)     @mandatory; // matches Materials.category, or 'default'
    autoOrderLimitValue : Decimal(10, 2) @mandatory; // max shortfall COST auto-orderable without approval
}

/**
 * Created only when a shortfall exceeds the auto-order limit.
 * The LLM writes riskLevel / recommendedActions / reasoning — nothing else on this entity
 * is LLM-generated; shortfallQty and shortfallValue are computed in code.
 */
entity Escalations : cuid, managed {
    productionOrder    : Association to ProductionOrders @mandatory;
    component          : Association to Materials        @mandatory;
    shortfallQty       : Integer                         @mandatory;
    shortfallValue     : Decimal(10, 2);
    riskLevel          : String(10); // low, medium, high — LLM-assessed
    recommendedActions : LargeString; // LLM structured output, stored as JSON string
    reasoning          : LargeString; // LLM's explanation
    status             : String(20) default 'pending-approval'; // pending-approval, approved, rejected
    rejectionReason    : String(200); // required when status = rejected
}

/**
 * The actual replenishment record — whether created automatically or after human approval.
 * `source` is the audit trail distinguishing agent autonomy from human decision.
 */
entity PurchaseOrders : cuid, managed {
    material   : Association to Materials @mandatory;
    quantity   : Integer                  @mandatory;
    escalation : Association to Escalations; // null when auto-ordered directly, no escalation needed
    status     : String(20) default 'created'; // created, sent, confirmed
    source     : String(20)               @mandatory; // 'agent-auto' or 'human-approved'
}
