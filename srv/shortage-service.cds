using {machbau.shortage as machbau} from '../db/schema';
using from './annotations/agentRelatedAnnotations';


service ShortageService  {
    entity Materials        as projection on machbau.Materials;
    entity MaterialsStock        as projection on machbau.MaterialStock;
    entity ProductionOrders as projection on machbau.ProductionOrders;
}
