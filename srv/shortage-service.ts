import cds from "@sap/cds";
export default class ShortageService extends cds.ApplicationService {
  async init() {
    const stock = await cds.connect.to("API_MATERIAL_STOCK_SRV");
    const productionOrders = await cds.connect.to("API_PRODUCTION_ORDER_2_SRV");
    const Products = await cds.connect.to("API_PRODUCT_SRV");

    this.on("READ", "Materials", async (req: Request) => {
      const { query } = req;
      const result = await Products.run(query);
      return result;
    });

    this.on("READ", "MaterialsStock", async (req: Request) => {
      const { query } = req;
      const result = await stock.run(query);
      return result;
    });

    this.on("READ", "ProductionOrders", async (req) => {
      const { query } = req;
      const result = await productionOrders.run(query);
      return result;
    });

    return super.init();
  }
}
