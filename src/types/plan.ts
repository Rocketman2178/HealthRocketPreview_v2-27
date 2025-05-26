export default interface Plan {
  id: string;
  name: string;
  description: string;
  price: number;
  interval: string;
  features: string[];
  price_id: string;
  is_active: boolean;
  icon: React.ComponentType<any>;
  comingSoon: boolean;
  trial_days?: number;
  promo_code?: boolean;
}

