require 'spec_helper'

describe "Customer Details", type: :feature, js: true do
  include OrderFeatureHelper

  stub_authorization!

  let(:country) { create(:country, name: "Kangaland") }
  let(:state) { create(:state, name: "Alabama", country: country) }
  let!(:shipping_method) { create(:shipping_method) }
  let!(:order) { create(:order, ship_address: ship_address, bill_address: bill_address, state: 'complete', completed_at: "2011-02-01 12:36:15") }
  let!(:product) { create(:product_in_stock) }

  # We need a unique name that will appear for the customer dropdown
  let!(:ship_address) { create(:address, country: country, state: state, first_name: "Rumpelstiltskin") }
  let!(:bill_address) { create(:address, country: country, state: state, first_name: "Rumpelstiltskin") }

  let!(:user) { create(:user, email: 'foobar@example.com', ship_address: ship_address, bill_address: bill_address) }

  context "brand new order" do
    let(:quantity) { 1 }

    before do
      visit spree.admin_path
      click_link "Orders"
      click_link "New Order"
      click_on 'Cart'

      add_line_item product.name, quantity: quantity

      expect(page).to have_css('.line-item')
      click_link "Customer"
      targetted_select2 "foobar@example.com", from: "#s2id_customer_search"
    end

    # Regression test for https://github.com/spree/spree/issues/3335 and https://github.com/spree/spree/issues/5317
    it "associates a user when not using guest checkout" do
      # 5317 - Address prefills using user's default.
      expect(page).to have_field('First Name', with: user.bill_address.firstname)
      expect(page).to have_field('Last Name', with: user.bill_address.lastname)
      expect(page).to have_field('Street Address', with: user.bill_address.address1)
      expect(page).to have_field("Street Address (cont'd)", with: user.bill_address.address2)
      expect(page).to have_field('City', with: user.bill_address.city)
      expect(page).to have_field('Zip Code', with: user.bill_address.zipcode)
      expect(page).to have_select('Country', selected: "United States of America", visible: false)
      expect(page).to have_select('State', selected: user.bill_address.state.name, visible: false)
      expect(page).to have_field('Phone', with: user.bill_address.phone)
      click_button "Update"
      expect(Spree::Order.last.user).not_to be_nil
    end

    context "when required quantity is more than available" do
      let(:quantity) { 11 }
      let!(:product) { create(:product_not_backorderable) }

      it "displays an error" do
        click_button "Update"
        expect(page).to have_content Spree.t(:insufficient_stock_for_order)
      end
    end
  end

  context "editing an order" do
    before do
      configure_spree_preferences do |config|
        config.default_country_iso = country.iso
        config.company = true
      end

      visit spree.admin_path
      click_link "Orders"
      within('table#listing_orders') { click_icon(:edit) }
    end

    context "selected country has no state" do
      before { create(:country, iso: "BRA", name: "Brazil") }

      it "changes state field to text input" do
        click_link "Customer"

        within("#billing") do
          targetted_select2 "Brazil", from: "#s2id_order_bill_address_attributes_country_id"
          fill_in "order_bill_address_attributes_state_name", with: "Piaui"
        end

        click_button "Update"
        expect(page).to have_content "Customer Details Updated"
        click_link "Customer"
        expect(page).to have_field("order_bill_address_attributes_state_name", with: "Piaui")
      end
    end

    it "should be able to update customer details for an existing order" do
      order.ship_address = create(:address)
      order.save!

      click_link "Customer"
      within("#shipping") { fill_in_address "ship" }
      within("#billing") { fill_in_address "bill" }

      click_button "Update"
      click_link "Customer"

      # Regression test for https://github.com/spree/spree/issues/2950 and https://github.com/spree/spree/issues/2433
      # This act should transition the state of the order as far as it will go too
      within("#order_tab_summary") do
        expect(find("dt#order_status + dd")).to have_content("complete")
      end
    end

    it "should show validation errors" do
      order.update_attributes!(ship_address_id: nil)
      click_link "Customer"
      click_button "Update"
      expect(page).to have_content("Shipping address first name can't be blank")
    end

    it "updates order email for an existing order with a user" do
      order.update_columns(ship_address_id: ship_address.id, bill_address_id: bill_address.id, state: "confirm", completed_at: nil)
      previous_user = order.user
      click_link "Customer"
      fill_in "order_email", with: "newemail@example.com"
      expect { click_button "Update" }.to change { order.reload.email }.to "newemail@example.com"
      expect(order.user_id).to eq previous_user.id
      expect(order.user.email).to eq previous_user.email
    end

    context "country associated was removed" do
      let(:brazil) { create(:country, iso: "BR", name: "Brazil") }

      before do
        order.bill_address.country.destroy
        configure_spree_preferences do |config|
          config.default_country_iso = brazil.iso
        end
      end

      it "sets default country when displaying form" do
        click_link "Customer"
        expect(page).to have_field("order_bill_address_attributes_country_id", with: brazil.id, visible: false)
      end
    end

    # Regression test for https://github.com/spree/spree/issues/942
    context "errors when no shipping methods are available" do
      before do
        Spree::ShippingMethod.delete_all
      end

      specify do
        click_link "Customer"
        # Need to fill in valid information so it passes validations
        fill_in "order_ship_address_attributes_firstname",  with: "John 99"
        fill_in "order_ship_address_attributes_lastname",   with: "Doe"
        fill_in "order_ship_address_attributes_lastname",   with: "Company"
        fill_in "order_ship_address_attributes_address1",   with: "100 first lane"
        fill_in "order_ship_address_attributes_address2",   with: "#101"
        fill_in "order_ship_address_attributes_city",       with: "Bethesda"
        fill_in "order_ship_address_attributes_zipcode",    with: "20170"

        select_state('Alabama', 'ship')
        fill_in "order_ship_address_attributes_phone", with: "123-456-7890"
        click_button "Update"
      end
    end
  end

  def select_state(state_name, kind = "bill")
    targetted_select2 state_name, from: "#s2id_order_#{kind}_address_attributes_state_id"
  end

  def fill_in_address(kind = "bill")
    fill_in "First Name",              with: "John 99"
    fill_in "Last Name",               with: "Doe"
    fill_in "Company",                 with: "Company"
    fill_in "Street Address",          with: "100 first lane"
    fill_in "Street Address (cont'd)", with: "#101"
    fill_in "City",                    with: "Bethesda"
    fill_in "Zip Code",                with: "20170"
    select_state("Alabama", kind)
    fill_in "Phone",                   with: "123-456-7890"
  end
end
