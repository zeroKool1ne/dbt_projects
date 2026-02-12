import streamlit as st
import snowflake.connector
import plotly.express as px
import pandas as pd

# -- page config --
st.set_page_config(page_title="E-Commerce Sales Dashboard", layout="wide")
st.title("E-Commerce Sales Dashboard")

# -- snowflake connection --
@st.cache_resource
def get_connection():
    return snowflake.connector.connect(
        account="qfxpmcv-td00620",
        user="DNLVSC",
        password="Daniel@Ironhack26!",
        warehouse="COMPUTE_WH",
        database="PREP",
        schema="HAND_ON_OUTPUT",
    )

@st.cache_data(ttl=600)
def run_query(query):
    conn = get_connection()
    cur = conn.cursor()
    cur.execute(query)
    columns = [desc[0] for desc in cur.description]
    data = cur.fetchall()
    return pd.DataFrame(data, columns=columns)


# -- load data --
monthly = run_query("SELECT * FROM mart_monthly_sales ORDER BY month")
by_category = run_query("SELECT * FROM mart_sales_by_category")
by_client_type = run_query("SELECT * FROM mart_sales_by_client_type")
by_client = run_query("SELECT * FROM mart_sales_by_client")
cube_cat_month = run_query("SELECT * FROM mart_cube_category_month WHERE category != 'ALL CATEGORIES' AND month != 'ALL MONTHS'")
cube_pay_status = run_query("SELECT * FROM mart_cube_payment_status WHERE payment_method != 'ALL METHODS' AND order_status != 'ALL STATUSES'")

fact = run_query("SELECT COUNT(DISTINCT order_id) AS orders, COUNT(DISTINCT client_id) AS clients, SUM(quantity) AS units, SUM(price_unit * quantity) AS revenue FROM fact_orders")


# -- KPI row --
st.markdown("### Key Metrics")
col1, col2, col3, col4 = st.columns(4)
col1.metric("Total Revenue", f"${fact['REVENUE'].iloc[0]:,.2f}")
col2.metric("Total Orders", f"{fact['ORDERS'].iloc[0]:,}")
col3.metric("Unique Clients", f"{fact['CLIENTS'].iloc[0]:,}")
col4.metric("Units Sold", f"{fact['UNITS'].iloc[0]:,.0f}")

st.divider()


# -- monthly sales chart --
st.markdown("### Monthly Sales")
monthly["MONTH"] = pd.to_datetime(monthly["MONTH"])
fig_monthly = px.bar(
    monthly,
    x="MONTH",
    y="TOTAL_REVENUE",
    text="TOTAL_REVENUE",
    labels={"MONTH": "Month", "TOTAL_REVENUE": "Revenue ($)"},
)
fig_monthly.update_traces(texttemplate="$%{text:,.0f}", textposition="outside")
fig_monthly.update_layout(xaxis_tickformat="%b %Y", showlegend=False)
st.plotly_chart(fig_monthly, use_container_width=True)

col_left, col_right = st.columns(2)


# -- sales by category --
with col_left:
    st.markdown("### Revenue by Product Category")
    fig_cat = px.pie(
        by_category,
        values="TOTAL_REVENUE",
        names="CATEGORY",
        hole=0.4,
    )
    fig_cat.update_traces(textinfo="label+percent", textposition="outside")
    st.plotly_chart(fig_cat, use_container_width=True)


# -- sales by client type --
with col_right:
    st.markdown("### Revenue by Client Type")
    fig_client_type = px.bar(
        by_client_type,
        x="CLIENT_TYPE",
        y="TOTAL_REVENUE",
        color="CLIENT_TYPE",
        text="TOTAL_REVENUE",
        labels={"CLIENT_TYPE": "Client Type", "TOTAL_REVENUE": "Revenue ($)"},
    )
    fig_client_type.update_traces(texttemplate="$%{text:,.0f}", textposition="outside")
    fig_client_type.update_layout(showlegend=False)
    st.plotly_chart(fig_client_type, use_container_width=True)


st.divider()
st.markdown("### CUBE Analysis")
col_cube_left, col_cube_right = st.columns(2)


# -- cube: category x month heatmap --
with col_cube_left:
    st.markdown("### Revenue by Category x Month")
    cube_cat_month["MONTH"] = pd.to_datetime(cube_cat_month["MONTH"])
    cube_cat_month["MONTH_STR"] = cube_cat_month["MONTH"].dt.strftime("%b %Y")
    fig_heatmap = px.density_heatmap(
        cube_cat_month,
        x="MONTH_STR",
        y="CATEGORY",
        z="TOTAL_REVENUE",
        color_continuous_scale="Blues",
        labels={"MONTH_STR": "Month", "CATEGORY": "Category", "TOTAL_REVENUE": "Revenue ($)"},
    )
    st.plotly_chart(fig_heatmap, use_container_width=True)


# -- cube: payment x status --
with col_cube_right:
    st.markdown("### Revenue by Payment Method x Order Status")
    fig_pay = px.bar(
        cube_pay_status,
        x="PAYMENT_METHOD",
        y="TOTAL_REVENUE",
        color="ORDER_STATUS",
        barmode="group",
        text="TOTAL_REVENUE",
        labels={"PAYMENT_METHOD": "Payment Method", "TOTAL_REVENUE": "Revenue ($)", "ORDER_STATUS": "Status"},
    )
    fig_pay.update_traces(texttemplate="$%{text:,.0f}", textposition="outside")
    st.plotly_chart(fig_pay, use_container_width=True)


# -- top clients --
st.divider()
st.markdown("### Top 10 Clients by Revenue")
top_clients = by_client.head(10)
fig_top = px.bar(
    top_clients,
    x="CLIENT_NAME",
    y="TOTAL_REVENUE",
    color="CLIENT_TYPE",
    text="TOTAL_REVENUE",
    labels={"CLIENT_NAME": "Client", "TOTAL_REVENUE": "Revenue ($)", "CLIENT_TYPE": "Type"},
)
fig_top.update_traces(texttemplate="$%{text:,.0f}", textposition="outside")
fig_top.update_layout(xaxis_tickangle=-45)
st.plotly_chart(fig_top, use_container_width=True)


# -- detail tables --
st.divider()
st.markdown("### Detail Tables")

tab1, tab2, tab3, tab4, tab5, tab6 = st.tabs([
    "Monthly Sales", "By Category", "By Client Type", "By Client",
    "Cube: Category x Month", "Cube: Payment x Status"
])

with tab1:
    st.dataframe(monthly, use_container_width=True)
with tab2:
    st.dataframe(by_category, use_container_width=True)
with tab3:
    st.dataframe(by_client_type, use_container_width=True)
with tab4:
    st.dataframe(by_client, use_container_width=True)
with tab5:
    full_cube_cat = run_query("SELECT * FROM mart_cube_category_month")
    st.dataframe(full_cube_cat, use_container_width=True)
with tab6:
    full_cube_pay = run_query("SELECT * FROM mart_cube_payment_status")
    st.dataframe(full_cube_pay, use_container_width=True)
