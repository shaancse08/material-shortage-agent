using {machbau.shortage as machbau} from '../db/schema';


service ShortageService {
    entity Materials        as projection on machbau.Materials;
    entity ProductionOrders as projection on machbau.ProductionOrders;
}
